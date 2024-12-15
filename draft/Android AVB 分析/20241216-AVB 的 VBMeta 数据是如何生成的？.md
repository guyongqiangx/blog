# 20241216-AVB 的 VBMeta 数据是如何生成的？

前面几篇分析了 boot.img 和 system.img 的布局，分别如下：



boot.img 文件布局

```
boot.img layout：
+----------------+  <-- 0
|                |
|   Boot Image   |
|                |
+----------------+  <-- original_image_size
|   VBMeta       |  <-- vbmeta_offset
|   (64KB max)   |
+----------------+
|                |
|   Padding      |
|                |
+----------------+  <-- Last 4KB offset
|   (4KB)        |
|   AVB Footer   |  <-- Last 64 bytes
+----------------+  <-- partition_size (64MB)
```



system.img 文件布局:

```
system.img layout (4K aligned):
+--------------------------------+ 0x0
|      System Image     |
|      (system partition)        |
+--------------------------------+ original_image_size
|                                |
|      Hash Tree                 |
|      (Merkle Tree)             |
|                                |
+--------------------------------+ tree_offset + tree_size
|                                |
|      FEC Data                  | (Optional)
|                                |
+--------------------------------+ fec_offset + fec_size
|      AVB VBMeta                |
|      - Header                  |
|      - Authentication Block    |
|      - Hashtree Descriptor     |
|      - Properties              |
+--------------------------------+ vbmeta_offset + vbmeta_size
|                                |
|      Padding                   |
|                                |
+--------------------------------+  <-- Last 4KB offset
|      (4KB)                     |
|      AVB Footer                |  <-- Last 64 bytes
+--------------------------------+  <-- partition_size
```



我们在前面《AVB 的哈希数据到底是如何生成的？》以及《AVB 的 FEC 数据到底是如何生成的？》分别分析了 hash tree 数据和 FEC 数据的生成。

但还没有触及 boot.img 和 system.img 中共同的 VBMeta 数据，本文专门针对 VBMeta 数据的生成进行分析。

这个 VBMeta 数据时整个 AVB 机制的核心，既可以位于镜像内部(如 boot.img 和 system.img 内部的 VBMeta)，也可以单独出来生成 vbmeta.img 这样的镜像文件。



## boot.img 中 VBMeta 数据的生成



## system.img 中 VBMeta 数据的生成

## vbmeta.img 镜像的生成