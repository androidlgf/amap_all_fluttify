import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';

import '../amap_all_fluttify.dart';
import 'models.dart';

const _iconSize = 50.0;
const _package = 'amap_all_fluttify';
const _indicator = 'images/indicator.png';
double _fabHeight = 16.0;

typedef Future<bool> RequestPermission();
typedef Widget PoiItemBuilder(Poi poi, bool selected);

class LocationPicker extends StatefulWidget {
  const LocationPicker({
    Key key,
    @required this.requestPermission,
    @required this.poiItemBuilder,
    this.zoomLevel = 16.0,
    this.zoomGesturesEnabled = false,
    this.showZoomControl = false,
    this.centerIndicator,
  })  : assert(zoomLevel != null && zoomLevel >= 3 && zoomLevel <= 19),
        super(key: key);

  /// 请求权限回调
  final RequestPermission requestPermission;

  /// Poi列表项Builder
  final PoiItemBuilder poiItemBuilder;

  /// 显示的缩放登记
  final double zoomLevel;

  /// 缩放手势使能 默认false
  final bool zoomGesturesEnabled;

  /// 是否显示缩放控件 默认false
  final bool showZoomControl;

  /// 地图中心指示器
  final Widget centerIndicator;

  @override
  _LocationPickerState createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker>
    with SingleTickerProviderStateMixin, _BLoCMixin, _AnimationMixin {
  // 地图控制器
  AmapController _controller;

  // 是否用户手势移动地图
  bool _moveByUser = true;

  @override
  Widget build(BuildContext context) {
    final minPanelHeight = MediaQuery.of(context).size.height * 0.4;
    final maxPanelHeight = MediaQuery.of(context).size.height * 0.7;
    return SlidingUpPanel(
      parallaxEnabled: true,
      parallaxOffset: 0.5,
      minHeight: minPanelHeight,
      maxHeight: maxPanelHeight,
      borderRadius: BorderRadius.circular(8),
      onPanelSlide: (double pos) => setState(() {
        _fabHeight = pos * (maxPanelHeight - minPanelHeight) * .5 + 16;
      }),
      body: Column(
        children: <Widget>[
          Flexible(
            child: Stack(
              children: <Widget>[
                AmapView(
                  zoomLevel: widget.zoomLevel,
                  zoomGesturesEnabled: widget.zoomGesturesEnabled,
                  showZoomControl: widget.showZoomControl,
                  onMapMoveEnd: (move) async {
                    if (_moveByUser) {
                      // 地图移动结束, 显示跳动动画
                      _jumpController
                          .forward()
                          .then((it) => _jumpController.reverse());
                      _search(move.latLng);
                    }
                    _moveByUser = true;
                  },
                  onMapCreated: (controller) async {
                    _controller = controller;
                    if (await widget.requestPermission()) {
                      await _showMyLocation();
                      _search(await _controller.getLocation());
                    } else {
                      debugPrint('权限请求被拒绝!');
                    }
                  },
                ),
                // 中心指示器
                Center(
                  child: AnimatedBuilder(
                    animation: _tween,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(
                          _tween.value.dx,
                          _tween.value.dy - _iconSize / 2,
                        ),
                        child: child,
                      );
                    },
                    child: widget.centerIndicator ??
                        Image.asset(
                          _indicator,
                          height: _iconSize,
                          package: _package,
                        ),
                  ),
                ),
                // 定位按钮
                Positioned(
                  right: 16.0,
                  bottom: _fabHeight,
                  child: FloatingActionButton(
                    child: StreamBuilder<bool>(
                      stream: _onMyLocation.stream,
                      initialData: true,
                      builder: (context, snapshot) {
                        return Icon(
                          Icons.gps_fixed,
                          color: snapshot.data
                              ? Theme.of(context).primaryColor
                              : Colors.black54,
                        );
                      },
                    ),
                    onPressed: _showMyLocation,
                    backgroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          // 用来抵消panel的最小高度
          SizedBox(height: minPanelHeight),
        ],
      ),
      panelBuilder: (scrollController) {
        return StreamBuilder<List<PoiInfo>>(
          stream: _poiStream.stream,
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              final data = snapshot.data;
              return ListView.builder(
                padding: EdgeInsets.zero,
                controller: scrollController,
                shrinkWrap: true,
                itemCount: data.length,
                itemBuilder: (context, index) {
                  final poi = data[index].poi;
                  final selected = data[index].selected;
                  return GestureDetector(
                    onTap: () {
                      for (int i = 0; i < data.length; i++) {
                        data[i].selected = i == index;
                      }
                      _onMyLocation.add(index == 0);
                      _poiStream.add(data);
                      _setCenterCoordinate(poi.latLng);
                    },
                    child: widget.poiItemBuilder(poi, selected),
                  );
                },
              );
            } else {
              return Center();
            }
          },
        );
      },
    );
  }

  Future<void> _search(LatLng location) async {
    AmapSearch.searchAround(location)
        .then((poiList) => poiList.map((poi) => PoiInfo(poi)).toList())
        // 默认勾选第一项
        .then((poiInfoList) => poiInfoList..[0].selected = true)
        .then(_poiStream.add);
  }

  Future<void> _showMyLocation() async {
    _onMyLocation.add(true);
    await _controller?.showMyLocation(MyLocationOption(
      strokeColor: Colors.transparent,
      fillColor: Colors.transparent,
    ));
  }

  Future<void> _setCenterCoordinate(LatLng coordinate) async {
    await _controller.setCenterCoordinate(
      coordinate.latitude,
      coordinate.longitude,
    );
    _moveByUser = false;
  }
}

mixin _BLoCMixin on State<LocationPicker> {
  // poi流
  final _poiStream = StreamController<List<PoiInfo>>();
  // 是否在我的位置
  final _onMyLocation = StreamController<bool>();

  @override
  void dispose() {
    _poiStream.close();
    _onMyLocation.close();
    super.dispose();
  }
}

mixin _AnimationMixin on SingleTickerProviderStateMixin<LocationPicker> {
  // 动画相关
  AnimationController _jumpController;
  Animation<Offset> _tween;

  @override
  void initState() {
    super.initState();
    _jumpController =
        AnimationController(vsync: this, duration: Duration(milliseconds: 300));
    _tween = Tween(begin: Offset(0, 0), end: Offset(0, -15)).animate(
        CurvedAnimation(parent: _jumpController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _jumpController?.dispose();
    super.dispose();
  }
}
