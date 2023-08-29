# 20230829-Android OTA 相关工具(六)  使用 lpmake 打包生成 super.img

> 本文为洛奇看世界(guyongqiangx)原创，转载请注明出处。
>
> 文章链接：https://blog.csdn.net/guyongqiangx/article/details/



```bash
rocky@guyongqiangx:/public/rocky/android-13.0.0_r41$ lpmake help
lpmake - command-line tool for creating Android Logical Partition images.

Usage:
  lpmake [options]

Required options:
  -d,--device-size=[SIZE|auto]  Size of the block device for logical partitions.
                                Can be set to auto to automatically calculate the
                                minimum size, the sum of partition sizes plus
                                metadata-size times the number of partitions.
  -m,--metadata-size=SIZE       Maximum size to reserve for partition metadata.
  -s,--metadata-slots=COUNT     Number of slots to store metadata copies.
  -p,--partition=DATA           Add a partition given the data, see below.
  -o,--output=FILE              Output file.

Optional:
  -b,--block-size=SIZE          Physical block size, defaults to 4096.
  -a,--alignment=N              Optimal partition alignment in bytes.
  -O,--alignment-offset=N       Alignment offset in bytes to device parent.
  -S,--sparse                   Output a sparse image for fastboot.
  -i,--image=PARTITION=FILE     If building a sparse image for fastboot, include
                                the given file (or sparse file) as initial data for
                                the named partition.
  -g,--group=GROUP:SIZE         Define a named partition group with the given
                                maximum size.
  -D,--device=DATA              Add a block device that the super partition
                                spans over. If specified, then -d/--device-size
                                and alignments must not be specified. The format
                                for DATA is listed below.
  -n,--super-name=NAME          Specify the name of the block device that will
                                house the super partition.
  -x,--auto-slot-suffixing      Mark the block device and partition names needing
                                slot suffixes before being used.
  -F,--force-full-image         Force a full image to be written even if no
                                partition images were specified. Normally, this
                                would produce a minimal super_empty.img which
                                cannot be flashed; force-full-image will produce
                                a flashable image.
  --virtual-ab                  Add the VIRTUAL_AB_DEVICE flag to the metadata
                                header. Note that the resulting super.img will
                                require a liblp capable of parsing a v1.2 header.

Partition data format:
  <name>:<attributes>:<size>[:group]
  Attrs must be 'none' or 'readonly'.

Device data format:
  <partition_name>:<size>[:<alignment>:<alignment_offset>]
  The partition name is the basename of the /dev/block/by-name/ path of the
  block device. The size is the device size in bytes. The alignment and
  alignment offset parameters are the same as -a/--alignment and 
  -O/--alignment-offset.
```

