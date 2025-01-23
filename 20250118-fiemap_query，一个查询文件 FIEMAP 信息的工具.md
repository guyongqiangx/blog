# 20250118-fiemap_query，一个查询文件 FIEMAP 信息的工具



## 1. 背景

在[《Android AVB 分析（十三）dm-verity 设备是如何映射的？》](https://blog.csdn.net/guyongqiangx/article/details/145211172)中，我演示过一个查询 system.img 镜像中 `init.envrion.rc` 文件布局的操作：

```bas
system-bare$ ls -al init.environ.rc 
-rwxr-x---. 1 root 2000 463 Jan  1  2009 init.environ.rc
system-bare$ sudo ../fiemap_query init.environ.rc 
File: init.environ.rc
Total extents: 1

Extent Details:
Logical      Physical     Length       Flags
----------------------------------------------
0x0          0x2d000      0x1000       LAST 
$ 
```



我们先将 system-bare.img 挂载到 `system-bare` 目录，然后在 `system-bare` 目录下通过 `fiemap_query init.environ.rc` 命令查询到了这个文件在 `system-bare.img` 镜像中的布局。



这里的 `fiemap_query` 就是我写的一个简单的用来查询文件布局的工具。



## 2. 什么是  fiemap?

fiemap 是 File Extent Map 的简称。

fiemap 是 Linux 文件系统中用于获取文件物理存储布局信息的机制。它能够告诉你一个文件在磁盘上是如何存储的，具体包括文件的数据块在磁盘上的物理位置和分布情况。

主要用途包括：

1. 文件碎片分析

   - 可以用来检查文件是否有碎片

   - 帮助确定是否需要进行碎片整理

2. 文件备份优化

   - 备份软件可以利用 fiemap 来实现更高效的增量备份

   - 可以直接读取变化的数据块，而不是扫描整个文件

3. 存储空间分析

   - 帮助了解文件实际占用的物理空间

   - 特别适用于稀疏文件(sparse file)的空间分析

4. 文件系统性能优化

   - 可以用来分析文件的物理布局是否最优

   - 帮助进行存储性能调优



Android 的 OTA 更新中，使用到了 FIEMAP 来从 /data 分区中分配多个文件用于虚拟分区的快照映射。



## 3. fiemap_query 源码

基于 linux fiemap ioctl 接口，我写了一个查询文件 FIEMAP 的工具: fiemap_query

> 更多关于 Linux 中 fiemap ioctl 的信息，请参考 linux 官方文档:
>
> - https://docs.kernel.org/filesystems/fiemap.html

完整的源码如下：

```c
/*
 *         File: fiemap_query.c
 *       Author: guyongqiangx
 *         Blog: https://blog.csdn.net/guyongqiangx
 *         Date: 2024/09/09
 *  Description: This program uses the FS_IOC_FIEMAP ioctl to query the extent
 *               information of a file. It allocates a large buffer to store the
 *               extent information, and then uses the ioctl to retrieve the
 *               extent information. The extent information is then printed to
 *               the console.
 *        Build: gcc -o fiemap_query fiemap_query.c
 *        Usage: fiemap_query <filename>
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <linux/fs.h>
#include <linux/fiemap.h>

#define EXTENT_COUNT 128

void print_extents(const char *filename) {
    int fd;
    unsigned long buf_size;
    struct fiemap *fiemap;
    
    fd = open(filename, O_RDONLY);
    if (fd < 0) {
        perror("open");
        return;
    }

    // 分配足够大的 buffer 来存储 extent 信息
    buf_size = sizeof(struct fiemap) + 
               EXTENT_COUNT * sizeof(struct fiemap_extent);
    fiemap = malloc(buf_size);
    if (!fiemap) {
        perror("malloc");
        close(fd);
        return;
    }
    memset(fiemap, 0, buf_size);

    // 设置 FIEMAP ioctl 参数
    fiemap->fm_length = ULLONG_MAX;  // 获取整个文件的映射
    fiemap->fm_flags = 0;
    fiemap->fm_extent_count = EXTENT_COUNT;

    // 执行 FIEMAP ioctl
    if (ioctl(fd, FS_IOC_FIEMAP, fiemap) < 0) {
        perror("ioctl(FS_IOC_FIEMAP)");
        free(fiemap);
        close(fd);
        return;
    }

    // 打印每个 extent 的信息
    printf("File: %s\n", filename);
    printf("Total extents: %d\n", fiemap->fm_mapped_extents);
    printf("\nExtent Details:\n");
    printf("%-12s %-12s %-12s %s\n", 
           "Logical", "Physical", "Length", "Flags");
    printf("----------------------------------------------\n");

    for (int i = 0; i < fiemap->fm_mapped_extents; i++) {
        struct fiemap_extent *extent = &fiemap->fm_extents[i];
        printf("0x%-10llx 0x%-10llx 0x%-10llx ",
               extent->fe_logical,
               extent->fe_physical,
               extent->fe_length);
        
        // 打印 flags
        if (extent->fe_flags & FIEMAP_EXTENT_LAST)
            printf("LAST ");
        if (extent->fe_flags & FIEMAP_EXTENT_UNKNOWN)
            printf("UNKNOWN ");
        if (extent->fe_flags & FIEMAP_EXTENT_DELALLOC)
            printf("DELALLOC ");
        if (extent->fe_flags & FIEMAP_EXTENT_ENCODED)
            printf("ENCODED ");
        if (extent->fe_flags & FIEMAP_EXTENT_DATA_ENCRYPTED)
            printf("ENCRYPTED ");
        if (extent->fe_flags & FIEMAP_EXTENT_NOT_ALIGNED)
            printf("NOT_ALIGNED ");
        if (extent->fe_flags & FIEMAP_EXTENT_DATA_INLINE)
            printf("INLINE ");
        if (extent->fe_flags & FIEMAP_EXTENT_DATA_TAIL)
            printf("TAIL ");
        if (extent->fe_flags & FIEMAP_EXTENT_UNWRITTEN)
            printf("UNWRITTEN ");
        if (extent->fe_flags & FIEMAP_EXTENT_MERGED)
            printf("MERGED ");

        printf("\n");
    }

    free(fiemap);
    close(fd);
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <filename>\n", argv[0]);
        return 1;
    }

    print_extents(argv[1]);
    return 0;
}
```



## 4. 编译和运行

### 4.1 编译

这个工具没有什么依赖，直接用 gcc 编译即可:

```bash
gcc -o fiemap_query fiemap_query.c
```



当然，你也可以根据你的需要，将这个工具整合到你的系统中。



### 4.2 运行

在 Ubuntu 上运行时需要 root 权限才能获取物理地址信息：

```
sudo ./fiemap_query /path/to/file
```

这个程序会显示文件的所有 extent 信息，包括它们的逻辑地址、物理地址、长度以及相关的标志。对于研究文件在磁盘上的实际布局很有帮助。



#### 示例一

例如，下面是我在 Android 编译服务器上查看 system.img 的布局信息：

```bash
$ fiemap_query /local/system.img
File: /local/system.img
Total extents: 38
Extent Details:
Logical      Physical     Length       Flags
----------------------------------------------
0x0          0x8e38a800000 0x5800000    
0x5800000    0x8e393000000 0x1000000    
0x6800000    0x8e396000000 0x2000000    
0x8800000    0x8e399800000 0x2800000    
0xb000000    0x8e39d000000 0x3000000    
0xe000000    0x8e3a5000000 0x7000000    
0x15000000   0x8e40a000000 0x2000000    
0x17000000   0x8e48d000000 0x5000000    
0x1c000000   0x8e492800000 0x800000     
0x1c800000   0x8e494000000 0x2000000    
0x1e800000   0x8e508000000 0x1000000    
0x1f800000   0x8e58b000000 0x1000000    
0x20800000   0x8eb17800000 0x2800000    
0x23000000   0x8eb1c000000 0x1000000    
0x24000000   0x8eb88800000 0x800000     
0x24800000   0x8eb8a000000 0x800000     
0x25000000   0x8eb8b800000 0x1000000    
0x26000000   0x8eb8d800000 0x800000     
0x26800000   0x8ec0a000000 0x800000     
0x27000000   0x8ec0d000000 0x800000     
0x27800000   0x8ec0c000000 0x1000000    
0x28800000   0x8ec0f000000 0x1000000    
0x29800000   0x8ec08000000 0x2000000    
0x2b800000   0x8ed89000000 0x800000     
0x2c000000   0x8ed8f000000 0x800000     
0x2c800000   0x8ed8b000000 0x1000000    
0x2d800000   0x8ee0a800000 0x1000000    
0x2e800000   0x8ee0c800000 0x2800000    
0x31000000   0x8ee88800000 0x2800000    
0x33800000   0x8ee8b800000 0x2000000    
0x35800000   0x8ee8e000000 0x1000000    
0x36800000   0x8ee90800000 0x1000000    
0x37800000   0x8ef08800000 0x1800000    
0x39000000   0x8ef0b000000 0x7800000    
0x40800000   0x8ef14000000 0x2000000    
0x42800000   0x8ef18000000 0x800000     
0x43000000   0x8ef88800000 0x1800000    
0x44800000   0x8ef8e000000 0x6d0000     LAST
```



从输出可以看到：

1. 这个 system.img 文件在磁盘上被分成了 38 个 extent 进行存储
2. 整个文件的大小约为：0x44800000 + 0x6d0000 = 0x44ed0000 字节 (≈ 1.15 GB)
3. 每个 extent 的大小不一，从 8MB (0x800000) 到 112MB (0x7000000) 不等



#### 示例二

在[《Android AVB 分析（十三）dm-verity 设备是如何映射的？》](https://blog.csdn.net/guyongqiangx/article/details/145211172)中，我演示过一个查询 system.img 镜像中 `init.envrion.rc` 文件的布局。



需要见将镜像 `system.img` 挂载到文件系统中，然后才能查询镜像的文件系统中某个文件的布局。

在提到的文章中，我将 `system-bare.img` 挂载到 `system-bare` 目录，然后在该目录中查询`init.environ.rc` 文件的布局信息：

```bas
system-bare$ ls -al init.environ.rc 
-rwxr-x---. 1 root 2000 463 Jan  1  2009 init.environ.rc
system-bare$ sudo ../fiemap_query init.environ.rc 
File: init.environ.rc
Total extents: 1

Extent Details:
Logical      Physical     Length       Flags
----------------------------------------------
0x0          0x2d000      0x1000       LAST 
$ 
```



从上面的信息中可以看到，`init.environ.rc` 文件的实际大小为 463 字节(Bytes)。



在设备上只占用了一个 extend，这个 extend 位于设备的 0x2d000 处，长度为 0x1000 (4096)。

因为是按照 block 分配存储，所以即使 `init.environ.rc` 文件只有  463 字节，但实际上也会分配一个 block。



## 5. 其它

我创建了一个 Android AVB 讨论群，主要讨论 Android 设备的 AVB 验证问题。

我还有几个 Android OTA 升级讨论群，主要讨论 Android 设备的 OTA 升级话题。

欢迎您加群和我们一起交流，请在加我微信时注明“Android AVB 交流”或“Android OTA 交流”。

仅限 Android 相关的开发者参与~

> 公众号“洛奇看世界”后台回复“wx”获取个人微信。



