# MusicCardX大图惯性补丁

基于photo_view0.15.0，保留MIT版权与许可证。

松手平移使用Flutter的ClampingScrollSimulation，默认摩擦系数0.015，与Android OverScroller滚动物理对齐。取消原来固定推进100px的弹簧动画；距离由松手速度决定，位置仍受图片边界限制。接触、拖动、双击切换倍率会停止旧惯性。

缩放、双击、图片边界和PhotoViewController接口保持原组件行为。Flutter实现与Android的总位移模型对齐，不宣称与每个厂商图库的全部手势逻辑一致。官方实现说明：https://api.flutter.dev/flutter/widgets/ClampingScrollSimulation-class.html 。

1.3.3修正：停止惯性移至外层Listener.onPointerDown；不再依赖TapGestureRecognizer的识别时机或可选的onTapDown回调。Flutter回归用真实指针按下、无移动来验证立即停住。
