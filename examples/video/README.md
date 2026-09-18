# 录像样例

[`mbmot-spatial-demo.mp4`](mbmot-spatial-demo.mp4) 是一段 90 帧、768×576、10 FPS 的无音轨样例。画面中的行人框由 OpenCV 全身 HOG 检测器产生，轨迹编号、生命周期、越线和区域统计由 MBMOT 处理，最后由 `tools/video_demo/video_demo.py` 绘制。

样例只用于展示数据链路和画面输出，不将这段录像的检测数量或轨迹数量作为精度指标。

原始画面取自 OpenCV 仓库的 [`samples/data/vtest.avi`](https://github.com/opencv/opencv/blob/4.x/samples/data/vtest.avi)，OpenCV 仓库采用 [Apache License 2.0](https://github.com/opencv/opencv/blob/4.x/LICENSE)。
