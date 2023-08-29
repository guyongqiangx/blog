# 20230829-Android OTA 相关工具(七)  使用 lpunpack 解包 super.img

> 本文为洛奇看世界(guyongqiangx)原创，转载请注明出处。
>
> 文章链接：https://blog.csdn.net/guyongqiangx/article/details/



我在 [《Android 动态分区详解(二) 核心模块和相关工具介绍》](https://guyongqiangx.blog.csdn.net/article/details/123931356) 有简单介绍过 lpdump 的用法。



```bash
rocky@guyongqiangx:/public/rocky/android-13.0.0_r41$ lpunpack -h
lpunpack - command-line tool for extracting partition images from super

Usage:
  lpunpack [options...] SUPER_IMAGE [OUTPUT_DIR]

Options:
  -p, --partition=NAME     Extract the named partition. This can
                           be specified multiple times.
  -S, --slot=NUM           Slot number (default is 0).
```



```bash
rocky@guyongqiangx:/public/rocky/android-13.0.0_r41$ find out -type f -iname *.img | grep super
out/target/product/panther/super_empty.img
out/target/product/panther/apex/com.android.virt/etc/fs/microdroid_super.img
out/target/product/panther/obj/ETC/microdroid_super.img.com.android.virt_intermediates/microdroid_super.img
out/target/product/panther/obj/PACKAGING/super.img_intermediates/super.img
out/target/product/panther/obj/PACKAGING/target_files_intermediates/aosp_panther-target_files-eng.rocky/IMAGES/super_empty.img
out/dist-new/super.img
out/dist-new/super_empty.img
out/soong/.intermediates/packages/modules/Virtualization/microdroid/microdroid_super/android_arm64_armv8-2a_cortex-a55/microdroid_super.img
out/soong/.intermediates/packages/modules/Virtualization/microdroid/microdroid_super/android_arm64_armv8-2a_cortex-a55/system_a.img
out/soong/.intermediates/packages/modules/Virtualization/microdroid/microdroid_super/android_arm64_armv8-2a_cortex-a55/vendor_a.img
out/soong/.intermediates/packages/modules/Virtualization/apex/com.android.virt/android_common_com.android.virt_image/image.apex/etc/fs/microdroid_super.img
out/dist-old/super.img
out/dist-old/super_empty.img
rocky@guyongqiangx:/public/rocky/android-13.0.0_r41$ mkdir temp
rocky@guyongqiangx:/public/rocky/android-13.0.0_r41$ simg2img out/dist-new/super.img super_raw.img 
rocky@guyongqiangx:/public/rocky/android-13.0.0_r41$ lpunpack super_raw.img temp/
rocky@guyongqiangx:/public/rocky/android-13.0.0_r41$ ls -lh temp/
total 2.1G
-rw-r--r-- 1 rocky users 351M Aug 29 14:09 product_a.img
-rw-r--r-- 1 rocky users    0 Aug 29 14:09 product_b.img
-rw-r--r-- 1 rocky users 846M Aug 29 14:09 system_a.img
-rw-r--r-- 1 rocky users  27M Aug 29 14:09 system_b.img
-rw-r--r-- 1 rocky users 340K Aug 29 14:09 system_dlkm_a.img
-rw-r--r-- 1 rocky users    0 Aug 29 14:09 system_dlkm_b.img
-rw-r--r-- 1 rocky users 288M Aug 29 14:09 system_ext_a.img
-rw-r--r-- 1 rocky users    0 Aug 29 14:09 system_ext_b.img
-rw-r--r-- 1 rocky users 593M Aug 29 14:09 vendor_a.img
-rw-r--r-- 1 rocky users    0 Aug 29 14:09 vendor_b.img
-rw-r--r-- 1 rocky users  42M Aug 29 14:09 vendor_dlkm_a.img
-rw-r--r-- 1 rocky users    0 Aug 29 14:09 vendor_dlkm_b.img
rocky@guyongqiangx:/public/rocky/android-13.0.0_r41$ 
```

