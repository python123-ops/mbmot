# 两条 MOT17 训练序列的本地批量复算

`src/mot_batch` 使用默认跟踪配置和 IoU 0.5 的 MoonBit 评测器，分别运行 `MOT17-02-FRCNN` 与 `MOT17-09-FRCNN`。两个序列在清单中分别建跟踪器，身份编号不跨序列关联。数据没有进入仓库；可以从 [MOT17 数据页](https://motchallenge.net/data/MOT17/) 获取原始数据。这次 09 序列的文本文件取自 [MOT17 文本镜像](https://huggingface.co/datasets/Lekim89/MOT17) 的提交 `f93908467986c77765667925a526ad07be8ad630`，02 序列沿用[先前记录](MOT17-02-FRCNN.md)中的文件。

| 序列 | 检测文件 SHA-256 | 标注文件 SHA-256 |
| --- | --- | --- |
| MOT17-02-FRCNN | `bbf9bc5e8fc40d7c6408385efa2a6794d12c3d09b57527eeebf90c055539bb2b` | `c013c83274ae1193b111b636fcbd0b4408096edb6927ecb91ea78b8beaa5deee` |
| MOT17-09-FRCNN | `8873ecccbbff2efc07e60c29dce1febd3ecf399c8ff93140dc7c9beb54ef218b` | `fe5dffe25c2c590f7dadcbacc45f7b1f2f2bcb7159ef3ac08b33d6428fc008ce` |

把每组 `det.txt`、`gt.txt` 放进 `benchmarks/data/<序列名>/`，并在未被版本控制的清单中列出两组路径。例如：

```json
{"sequences":[{"name":"MOT17-02-FRCNN","detections":"benchmarks/data/MOT17-02-FRCNN/det.txt","ground_truth":"benchmarks/data/MOT17-02-FRCNN/gt.txt"},{"name":"MOT17-09-FRCNN","detections":"benchmarks/data/MOT17-09-FRCNN/det.txt","ground_truth":"benchmarks/data/MOT17-09-FRCNN/gt.txt"}]}
```

在仓库根目录执行 `moon run src/mot_batch --target native --release -- benchmarks/data/two-frcnn.json`，本次得到：

| 范围 | 帧 | 标注框 | 跟踪框 | TP | FP | FN | IDSW | MOTA | IDF1 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| MOT17-02-FRCNN | 600 | 18,581 | 7,881 | 6,422 | 1,459 | 12,159 | 112 | 0.2610731392 | 0.3783538659 |
| MOT17-09-FRCNN | 525 | 5,325 | 3,005 | 2,988 | 17 | 2,337 | 31 | 0.5521126761 | 0.5827130852 |
| 合计 | 1,125 | 23,906 | 10,886 | 9,410 | 1,476 | 14,496 | 143 | 0.3259014473 | 0.4272821338 |

合计 MOTA、IDF1 和 MOTP 均由原始计数及匹配 IoU 之和重算，不是两行指标的平均数。这是未执行 MOTChallenge distractor、类别和忽略区域预处理的代码回归口径；不能与[02 序列的 TrackEval 预处理结果](MOT17-02-FRCNN.md)混用，也不是官方榜单成绩。
