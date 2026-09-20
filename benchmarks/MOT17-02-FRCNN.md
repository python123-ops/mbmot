# MOT17-02-FRCNN 复算记录

这次运行使用 MOT17 训练集的 `MOT17-02-FRCNN` 检测文件。序列包含 600 帧，检测文件有 8,186 行。文件中的帧并非按行号递增，`parse_detections` 会先按帧排序，同时保留同一帧内的原始检测顺序。

原始数据不进入仓库。可以从 [MOT17 数据页](https://motchallenge.net/data/MOT17/) 下载完整数据；本次运行从公开镜像取得同名的检测、标注和 `seqinfo.ini` 文件。复算前应核对：

```text
bbf9bc5e8fc40d7c6408385efa2a6794d12c3d09b57527eeebf90c055539bb2b  det.txt
c013c83274ae1193b111b636fcbd0b4408096edb6927ecb91ea78b8beaa5deee  gt.txt
f1a49690513a8e7c2f1c237f5aa121e3fedb95d71065fac2348ef532dfa432d7  seqinfo.ini
```

将文件放在 `benchmarks/data/MOT17-02-FRCNN/` 后运行：

```bash
moon run --target native --release src/mot_track \
  benchmarks/data/MOT17-02-FRCNN/det.txt \
  benchmarks/data/MOT17-02-FRCNN/mbmot.txt

moon run --target native --release src/evaluate \
  benchmarks/data/MOT17-02-FRCNN/gt.txt \
  benchmarks/data/MOT17-02-FRCNN/mbmot.txt
```

跟踪使用 `TrackerConfig::default()`，所有检测使用类别 `0`。生成文件有 7,881 行，SHA-256 为 `354f0c386285759bb8c818e6f376d7bec167399d99947054cd51398b66d90d24`。

MoonBit 评测器在 IoU 0.5 下得到 6,422 TP、1,459 FP、12,159 FN 和 112 次身份切换，对应 MOTA 0.2610731392、MOTP 0.8814040645、IDF1 0.3783538659。这个入口有意不执行 MOTChallenge 的 distractor 与类别预处理，适合固定输入的代码回归。

[TrackEval](https://github.com/JonathonLuiten/TrackEval) 提交 `12c8791b303e0a0b50f753af204249e622d0281a` 在 `DO_PREPROC=True` 下得到：

| HOTA | MOTA | MOTP | IDF1 | IDP | IDR | IDSW | TP | FP | FN |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 34.895 | 32.404 | 88.170 | 39.606 | 74.739 | 26.941 | 111 | 6,415 | 283 | 12,166 |

这里是训练序列上的一次可复算运行，不是 MOTChallenge 测试集排行榜成绩。TrackEval 预处理后保留 6,698 个轨迹框，因此它与上面的无预处理计数不能直接混用。

跟踪阶段在 Windows 11 64 位、Intel Core i9-14900HX 上以 release native 可执行文件连续运行五次，耗时为 146.265、133.259、127.638、132.008 和 137.739 ms，中位数 133.259 ms。计时只包含读取检测文本、跟踪和写出结果，不包含图像、检测推理、构建或 TrackEval。工具链为 `moon 0.1.20260904`、`moonc v0.10.12+1634b282e`。
