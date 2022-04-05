# Android 系统 image 是如何编译出来的？

## 1. 使用 `build_image.py`

### 1.1 system.img

```makefile
# stbszx-bld-2:/public/ygu/android-q-ab2/src-km
# build/core/Makefile

systemimage_intermediates := \
    $(call intermediates-dir-for,PACKAGING,systemimage)
BUILT_SYSTEMIMAGE := $(systemimage_intermediates)/system.img

# $(1): output file
define build-systemimage-target
  @echo "Target system fs image: $(1)"
  $(call create-system-vendor-symlink)
  $(call create-system-product-symlink)
  $(call create-system-product_services-symlink)
  $(call check-apex-libs-absence-on-disk)
  @mkdir -p $(dir $(1)) $(systemimage_intermediates) && rm -rf $(systemimage_intermediates)/system_image_info.txt
  $(call generate-image-prop-dictionary, $(systemimage_intermediates)/system_image_info.txt,system, \
      skip_fsck=true)
  $(hide) PATH=$(foreach p,$(INTERNAL_USERIMAGES_BINARY_PATHS),$(p):)$$PATH \
      build/make/tools/releasetools/build_image.py \
      $(TARGET_OUT) $(systemimage_intermediates)/system_image_info.txt $(1) $(TARGET_OUT) \
      || ( mkdir -p $${DIST_DIR}; cp $(INSTALLED_FILES_FILE) $${DIST_DIR}/installed-files-rescued.txt; \
           exit 1 )
endef

$(BUILT_SYSTEMIMAGE): $(FULL_SYSTEMIMAGE_DEPS) $(INSTALLED_FILES_FILE) $(BUILD_IMAGE_SRCS)
	$(call build-systemimage-target,$@)
```



#### system_image_info.txt

```shell
$ find out -type f -iname system_image_info.txt
out/target/product/inuvik/obj/PACKAGING/systemimage_intermediates/system_image_info.txt
$ cat out/target/product/inuvik/obj/PACKAGING/systemimage_intermediates/system_image_info.txt
system_journal_size=0
ext_mkuserimg=mkuserimg_mke2fs
fs_type=ext4
extfs_sparse_flag=-s
squashfs_sparse_flag=-s
ext4_share_dup_blocks=true
selinux_fc=out/target/product/inuvik/obj/ETC/file_contexts.bin_intermediates/file_contexts.bin
avb_avbtool=avbtool
avb_system_hashtree_enable=true
avb_system_add_hashtree_footer_args=--prop com.android.build.system.os_version:10 --prop com.android.build.system.security_patch:2020-11-05
avb_system_other_hashtree_enable=true
avb_system_other_add_hashtree_footer_args=
avb_vendor_hashtree_enable=true
avb_vendor_add_hashtree_footer_args=--prop com.android.build.vendor.os_version:10 --prop com.android.build.vendor.security_patch:2020-10-05
avb_product_hashtree_enable=true
avb_product_add_hashtree_footer_args=--prop com.android.build.product.os_version:10 --prop com.android.build.product.security_patch:2020-11-05
avb_product_services_hashtree_enable=true
avb_product_services_add_hashtree_footer_args=--prop com.android.build.product_services.os_version:10 --prop com.android.build.product_services.security_patch:2020-11-05
avb_odm_hashtree_enable=true
avb_odm_add_hashtree_footer_args=--prop com.android.build.odm.os_version:10
recovery_as_boot=true
root_dir=out/target/product/inuvik/root
use_dynamic_partition_size=true
skip_fsck=true
```

#### build_image.py 的参数

```python
# build_image.py
# argv[0]: in_dir
# argv[1]: glob_dict_file
# argv[2]: out_file
# argv[3]: target_out

build/make/tools/releasetools/build_image.py \
      $(TARGET_OUT) \
			$(systemimage_intermediates)/system_image_info.txt \
			$(systemimage_intermediates)/system.img \
			$(TARGET_OUT)

argv[0] =         in_dir = $(TARGET_OUT)
argv[1] = glob_dict_file = $(systemimage_intermediates)/system_image_info.txt
argv[2] =       out_file = $(systemimage_intermediates)/system.img
argv[3] =     target_out = $(TARGET_OUT)

BuildImage(in_dir, image_properties, out_file, target_out)
    in_dir: Path to input directory.
 prop_dict: A property dict that contains info like partition size. Values will be updated with computed values.
  out_file: The output image file.
target_out: Path to the TARGET_OUT directory as in Makefile.

size = GetDiskUsage(in_dir)
# size = $(du -k -s $in_dir)
# $ du -k -s out/target/product/inuvik/root
# 168     out/target/product/inuvik/root
BuildImageMkfs(in_dir, prop_dict, out_file, target_out, fs_config)

```



### 1.2 userdata.img

```makefile
userdataimage_intermediates := \
    $(call intermediates-dir-for,PACKAGING,userdata)
BUILT_USERDATAIMAGE_TARGET := $(PRODUCT_OUT)/userdata.img

define build-userdataimage-target
  $(call pretty,"Target userdata fs image: $(INSTALLED_USERDATAIMAGE_TARGET)")
  @mkdir -p $(TARGET_OUT_DATA)
  @mkdir -p $(userdataimage_intermediates) && rm -rf $(userdataimage_intermediates)/userdata_image_info.txt
  $(call generate-image-prop-dictionary, $(userdataimage_intermediates)/userdata_image_info.txt,userdata,skip_fsck=true)
  $(hide) PATH=$(foreach p,$(INTERNAL_USERIMAGES_BINARY_PATHS),$(p):)$$PATH \
      build/make/tools/releasetools/build_image.py \
      $(TARGET_OUT_DATA) $(userdataimage_intermediates)/userdata_image_info.txt $(INSTALLED_USERDATAIMAGE_TARGET) $(TARGET_OUT)
  $(hide) $(call assert-max-image-size,$(INSTALLED_USERDATAIMAGE_TARGET),$(BOARD_USERDATAIMAGE_PARTITION_SIZE))
endef

# We just build this directly to the install location.
INSTALLED_USERDATAIMAGE_TARGET := $(BUILT_USERDATAIMAGE_TARGET)
INSTALLED_USERDATAIMAGE_TARGET_DEPS := \
    $(INTERNAL_USERIMAGES_DEPS) \
    $(INTERNAL_USERDATAIMAGE_FILES) \
    $(BUILD_IMAGE_SRCS)
$(INSTALLED_USERDATAIMAGE_TARGET): $(INSTALLED_USERDATAIMAGE_TARGET_DEPS)
	$(build-userdataimage-target)
```

#### userdata_image_info.txt

```shell
$ find out -type f -iname userdata_image_info.txt
out/target/product/inuvik/obj/PACKAGING/userdata_intermediates/userdata_image_info.txt
$ cat out/target/product/inuvik/obj/PACKAGING/userdata_intermediates/userdata_image_info.txt
userdata_fs_type=f2fs
userdata_size=4441767936
ext_mkuserimg=mkuserimg_mke2fs
fs_type=ext4
extfs_sparse_flag=-s
squashfs_sparse_flag=-s
ext4_share_dup_blocks=true
selinux_fc=out/target/product/inuvik/obj/ETC/file_contexts.bin_intermediates/file_contexts.bin
avb_avbtool=avbtool
avb_system_hashtree_enable=true
avb_system_add_hashtree_footer_args=--prop com.android.build.system.os_version:10 --prop com.android.build.system.security_patch:2020-11-05
avb_system_other_hashtree_enable=true
avb_system_other_add_hashtree_footer_args=
avb_vendor_hashtree_enable=true
avb_vendor_add_hashtree_footer_args=--prop com.android.build.vendor.os_version:10 --prop com.android.build.vendor.security_patch:2020-10-05
avb_product_hashtree_enable=true
avb_product_add_hashtree_footer_args=--prop com.android.build.product.os_version:10 --prop com.android.build.product.security_patch:2020-11-05
avb_product_services_hashtree_enable=true
avb_product_services_add_hashtree_footer_args=--prop com.android.build.product_services.os_version:10 --prop com.android.build.product_services.security_patch:2020-11-05
avb_odm_hashtree_enable=true
avb_odm_add_hashtree_footer_args=--prop com.android.build.odm.os_version:10
recovery_as_boot=true
root_dir=out/target/product/inuvik/root
use_dynamic_partition_size=true
skip_fsck=true
```



### 1.3 cache.img

```makefile
cacheimage_intermediates := \
    $(call intermediates-dir-for,PACKAGING,cache)
BUILT_CACHEIMAGE_TARGET := $(PRODUCT_OUT)/cache.img

define build-cacheimage-target
  $(call pretty,"Target cache fs image: $(INSTALLED_CACHEIMAGE_TARGET)")
  @mkdir -p $(TARGET_OUT_CACHE)
  @mkdir -p $(cacheimage_intermediates) && rm -rf $(cacheimage_intermediates)/cache_image_info.txt
  $(call generate-image-prop-dictionary, $(cacheimage_intermediates)/cache_image_info.txt,cache,skip_fsck=true)
  $(hide) PATH=$(foreach p,$(INTERNAL_USERIMAGES_BINARY_PATHS),$(p):)$$PATH \
      build/make/tools/releasetools/build_image.py \
      $(TARGET_OUT_CACHE) $(cacheimage_intermediates)/cache_image_info.txt $(INSTALLED_CACHEIMAGE_TARGET) $(TARGET_OUT)
  $(hide) $(call assert-max-image-size,$(INSTALLED_CACHEIMAGE_TARGET),$(BOARD_CACHEIMAGE_PARTITION_SIZE))
endef

# We just build this directly to the install location.
INSTALLED_CACHEIMAGE_TARGET := $(BUILT_CACHEIMAGE_TARGET)
$(INSTALLED_CACHEIMAGE_TARGET): $(INTERNAL_USERIMAGES_DEPS) $(INTERNAL_CACHEIMAGE_FILES) $(BUILD_IMAGE_SRCS)
	$(build-cacheimage-target)
```

#### cache_image_info.txt

```shell
$ find out -type f -iname cache_image_info.txt
out/target/product/inuvik/obj/PACKAGING/cache_intermediates/cache_image_info.txt
$ cat out/target/product/inuvik/obj/PACKAGING/cache_intermediates/cache_image_info.txt
cache_fs_type=ext4
cache_size=6291456
ext_mkuserimg=mkuserimg_mke2fs
fs_type=ext4
extfs_sparse_flag=-s
squashfs_sparse_flag=-s
ext4_share_dup_blocks=true
selinux_fc=out/target/product/inuvik/obj/ETC/file_contexts.bin_intermediates/file_contexts.bin
avb_avbtool=avbtool
avb_system_hashtree_enable=true
avb_system_add_hashtree_footer_args=--prop com.android.build.system.os_version:10 --prop com.android.build.system.security_patch:2020-11-05
avb_system_other_hashtree_enable=true
avb_system_other_add_hashtree_footer_args=
avb_vendor_hashtree_enable=true
avb_vendor_add_hashtree_footer_args=--prop com.android.build.vendor.os_version:10 --prop com.android.build.vendor.security_patch:2020-10-05
avb_product_hashtree_enable=true
avb_product_add_hashtree_footer_args=--prop com.android.build.product.os_version:10 --prop com.android.build.product.security_patch:2020-11-05
avb_product_services_hashtree_enable=true
avb_product_services_add_hashtree_footer_args=--prop com.android.build.product_services.os_version:10 --prop com.android.build.product_services.security_patch:2020-11-05
avb_odm_hashtree_enable=true
avb_odm_add_hashtree_footer_args=--prop com.android.build.odm.os_version:10
recovery_as_boot=true
root_dir=out/target/product/inuvik/root
use_dynamic_partition_size=true
skip_fsck=true
```



### 1.4 system_other.img

```makefile
systemotherimage_intermediates := \
    $(call intermediates-dir-for,PACKAGING,system_other)
BUILT_SYSTEMOTHERIMAGE_TARGET := $(PRODUCT_OUT)/system_other.img

# Note that we assert the size is SYSTEMIMAGE_PARTITION_SIZE since this is the 'b' system image.
define build-systemotherimage-target
  $(call pretty,"Target system_other fs image: $(INSTALLED_SYSTEMOTHERIMAGE_TARGET)")
  @mkdir -p $(TARGET_OUT_SYSTEM_OTHER)
  @mkdir -p $(systemotherimage_intermediates) && rm -rf $(systemotherimage_intermediates)/system_other_image_info.txt
  $(call generate-image-prop-dictionary, $(systemotherimage_intermediates)/system_other_image_info.txt,system,skip_fsck=true)
  $(hide) PATH=$(foreach p,$(INTERNAL_USERIMAGES_BINARY_PATHS),$(p):)$$PATH \
      build/make/tools/releasetools/build_image.py \
      $(TARGET_OUT_SYSTEM_OTHER) $(systemotherimage_intermediates)/system_other_image_info.txt $(INSTALLED_SYSTEMOTHERIMAGE_TARGET) $(TARGET_OUT)
  $(hide) $(call assert-max-image-size,$(INSTALLED_SYSTEMOTHERIMAGE_TARGET),$(BOARD_SYSTEMIMAGE_PARTITION_SIZE))
endef

# We just build this directly to the install location.
INSTALLED_SYSTEMOTHERIMAGE_TARGET := $(BUILT_SYSTEMOTHERIMAGE_TARGET)
ifneq (true,$(SANITIZE_LITE))
# Only create system_other when not building the second stage of a SANITIZE_LITE build.
$(INSTALLED_SYSTEMOTHERIMAGE_TARGET): $(INTERNAL_USERIMAGES_DEPS) $(INTERNAL_SYSTEMOTHERIMAGE_FILES) $(INSTALLED_FILES_FILE_SYSTEMOTHER)
	$(build-systemotherimage-target)
endif
```



### 1.5 vendor.img

```makefile
vendorimage_intermediates := \
    $(call intermediates-dir-for,PACKAGING,vendor)
BUILT_VENDORIMAGE_TARGET := $(PRODUCT_OUT)/vendor.img
define build-vendorimage-target
  $(call pretty,"Target vendor fs image: $(INSTALLED_VENDORIMAGE_TARGET)")
  @mkdir -p $(TARGET_OUT_VENDOR)
  $(call create-vendor-odm-symlink)
  @mkdir -p $(vendorimage_intermediates) && rm -rf $(vendorimage_intermediates)/vendor_image_info.txt
  $(call generate-image-prop-dictionary, $(vendorimage_intermediates)/vendor_image_info.txt,vendor,skip_fsck=true)
  $(if $(BOARD_VENDOR_KERNEL_MODULES), \
    $(call build-image-kernel-modules,$(BOARD_VENDOR_KERNEL_MODULES),$(TARGET_OUT_VENDOR),vendor/,$(call intermediates-dir-for,PACKAGING,depmod_vendor)))
  $(hide) PATH=$(foreach p,$(INTERNAL_USERIMAGES_BINARY_PATHS),$(p):)$$PATH \
      build/make/tools/releasetools/build_image.py \
      $(TARGET_OUT_VENDOR) $(vendorimage_intermediates)/vendor_image_info.txt $(INSTALLED_VENDORIMAGE_TARGET) $(TARGET_OUT)
  $(hide) $(call assert-max-image-size,$(INSTALLED_VENDORIMAGE_TARGET),$(BOARD_VENDORIMAGE_PARTITION_SIZE))
endef

# We just build this directly to the install location.
INSTALLED_VENDORIMAGE_TARGET := $(BUILT_VENDORIMAGE_TARGET)
ifdef BUILT_VENDOR_MANIFEST
$(INSTALLED_VENDORIMAGE_TARGET): $(BUILT_ASSEMBLED_VENDOR_MANIFEST)
endif
$(INSTALLED_VENDORIMAGE_TARGET): $(INTERNAL_USERIMAGES_DEPS) $(INTERNAL_VENDORIMAGE_FILES) $(INSTALLED_FILES_FILE_VENDOR) $(BUILD_IMAGE_SRCS) $(DEPMOD) $(BOARD_VENDOR_KERNEL_MODULES)
	$(build-vendorimage-target)
```

#### vendor_image_info.txt

```shell
$ find out -type f -iname vendor_image_info.txt
out/target/product/inuvik/obj/PACKAGING/vendor_intermediates/vendor_image_info.txt
$ cat out/target/product/inuvik/obj/PACKAGING/vendor_intermediates/vendor_image_info.txt
vendor_fs_type=ext4
ext_mkuserimg=mkuserimg_mke2fs
fs_type=ext4
extfs_sparse_flag=-s
squashfs_sparse_flag=-s
ext4_share_dup_blocks=true
selinux_fc=out/target/product/inuvik/obj/ETC/file_contexts.bin_intermediates/file_contexts.bin
avb_avbtool=avbtool
avb_system_hashtree_enable=true
avb_system_add_hashtree_footer_args=--prop com.android.build.system.os_version:10 --prop com.android.build.system.security_patch:2020-11-05
avb_system_other_hashtree_enable=true
avb_system_other_add_hashtree_footer_args=
avb_vendor_hashtree_enable=true
avb_vendor_add_hashtree_footer_args=--prop com.android.build.vendor.os_version:10 --prop com.android.build.vendor.security_patch:2020-10-05
avb_product_hashtree_enable=true
avb_product_add_hashtree_footer_args=--prop com.android.build.product.os_version:10 --prop com.android.build.product.security_patch:2020-11-05
avb_product_services_hashtree_enable=true
avb_product_services_add_hashtree_footer_args=--prop com.android.build.product_services.os_version:10 --prop com.android.build.product_services.security_patch:2020-11-05
avb_odm_hashtree_enable=true
avb_odm_add_hashtree_footer_args=--prop com.android.build.odm.os_version:10
recovery_as_boot=true
root_dir=out/target/product/inuvik/root
use_dynamic_partition_size=true
skip_fsck=true
```



### 1.6 product.img

```makefile
productimage_intermediates := \
    $(call intermediates-dir-for,PACKAGING,product)
BUILT_PRODUCTIMAGE_TARGET := $(PRODUCT_OUT)/product.img
define build-productimage-target
  $(call pretty,"Target product fs image: $(INSTALLED_PRODUCTIMAGE_TARGET)")
  @mkdir -p $(TARGET_OUT_PRODUCT)
  @mkdir -p $(productimage_intermediates) && rm -rf $(productimage_intermediates)/product_image_info.txt
  $(call generate-image-prop-dictionary, $(productimage_intermediates)/product_image_info.txt,product,skip_fsck=true)
  $(hide) PATH=$(foreach p,$(INTERNAL_USERIMAGES_BINARY_PATHS),$(p):)$$PATH \
      ./build/tools/releasetools/build_image.py \
      $(TARGET_OUT_PRODUCT) $(productimage_intermediates)/product_image_info.txt $(INSTALLED_PRODUCTIMAGE_TARGET) $(TARGET_OUT)
  $(hide) $(call assert-max-image-size,$(INSTALLED_PRODUCTIMAGE_TARGET),$(BOARD_PRODUCTIMAGE_PARTITION_SIZE))
endef

# We just build this directly to the install location.
INSTALLED_PRODUCTIMAGE_TARGET := $(BUILT_PRODUCTIMAGE_TARGET)
$(INSTALLED_PRODUCTIMAGE_TARGET): $(INTERNAL_USERIMAGES_DEPS) $(INTERNAL_PRODUCTIMAGE_FILES) $(INSTALLED_FILES_FILE_PRODUCT) $(BUILD_IMAGE_SRCS)
	$(build-productimage-target)
```



### 1.7 product_services.img

```makefile
product_servicesimage_intermediates := \
    $(call intermediates-dir-for,PACKAGING,product_services)
BUILT_PRODUCT_SERVICESIMAGE_TARGET := $(PRODUCT_OUT)/product_services.img
define build-product_servicesimage-target
  $(call pretty,"Target product_services fs image: $(INSTALLED_PRODUCT_SERVICESIMAGE_TARGET)")
  @mkdir -p $(TARGET_OUT_PRODUCT_SERVICES)
  @mkdir -p $(product_servicesimage_intermediates) && rm -rf $(product_servicesimage_intermediates)/product_services_image_info.txt
  $(call generate-image-prop-dictionary, $(product_servicesimage_intermediates)/product_services_image_info.txt,product_services, skip_fsck=true)
  $(hide) PATH=$(foreach p,$(INTERNAL_USERIMAGES_BINARY_PATHS),$(p):)$$PATH \
      ./build/tools/releasetools/build_image.py \
      $(TARGET_OUT_PRODUCT_SERVICES) $(product_servicesimage_intermediates)/product_services_image_info.txt $(INSTALLED_PRODUCT_SERVICESIMAGE_TARGET) $(TARGET_OUT)
  $(hide) $(call assert-max-image-size,$(INSTALLED_PRODUCT_SERVICESIMAGE_TARGET),$(BOARD_PRODUCT_SERVICESIMAGE_PARTITION_SIZE))
endef

# We just build this directly to the install location.
INSTALLED_PRODUCT_SERVICESIMAGE_TARGET := $(BUILT_PRODUCT_SERVICESIMAGE_TARGET)
$(INSTALLED_PRODUCT_SERVICESIMAGE_TARGET): $(INTERNAL_USERIMAGES_DEPS) $(INTERNAL_PRODUCT_SERVICESIMAGE_FILES) $(INSTALLED_FILES_FILE_PRODUCT_SERVICES) $(BUILD_IMAGE_SRCS)
	$(build-product_servicesimage-target)
```



### 1.8 odm.img

```makefile
odmimage_intermediates := \
    $(call intermediates-dir-for,PACKAGING,odm)
BUILT_ODMIMAGE_TARGET := $(PRODUCT_OUT)/odm.img
define build-odmimage-target
  $(call pretty,"Target odm fs image: $(INSTALLED_ODMIMAGE_TARGET)")
  @mkdir -p $(TARGET_OUT_ODM)
  @mkdir -p $(odmimage_intermediates) && rm -rf $(odmimage_intermediates)/odm_image_info.txt
  $(call generate-userimage-prop-dictionary, $(odmimage_intermediates)/odm_image_info.txt, skip_fsck=true)
  $(if $(BOARD_ODM_KERNEL_MODULES), \
    $(call build-image-kernel-modules,$(BOARD_ODM_KERNEL_MODULES),$(TARGET_OUT_ODM),odm/,$(call intermediates-dir-for,PACKAGING,depmod_odm)))
  $(hide) PATH=$(foreach p,$(INTERNAL_USERIMAGES_BINARY_PATHS),$(p):)$$PATH \
      ./build/tools/releasetools/build_image.py \
      $(TARGET_OUT_ODM) $(odmimage_intermediates)/odm_image_info.txt $(INSTALLED_ODMIMAGE_TARGET) $(TARGET_OUT)
  $(hide) $(call assert-max-image-size,$(INSTALLED_ODMIMAGE_TARGET),$(BOARD_ODMIMAGE_PARTITION_SIZE))
endef

# We just build this directly to the install location.
INSTALLED_ODMIMAGE_TARGET := $(BUILT_ODMIMAGE_TARGET)
$(INSTALLED_ODMIMAGE_TARGET): $(INTERNAL_USERIMAGES_DEPS) $(INTERNAL_ODMIMAGE_FILES) $(INSTALLED_FILES_FILE_ODM) $(BUILD_IMAGE_SRCS) $(DEPMOD) $(BOARD_ODM_KERNEL_MODULES)
	$(build-odmimage-target)
```

---

### 1.9 mkuserimg_mke2fs

system.img 生成命令

```bash
# system.img
mkuserimg_mke2fs -s \ (android sparse file)
	  out/soong/.temp/tmphevMBR \ (src_dir)
		system.img \ (output_file)
		ext4 / 1125830656 \ ({ext2,ext4}, mount_point, fs_size)
		-j 0 \ (JOURNAL_SIZE)
		-T 1230768000 \ (TIMESTAMP)
		-C out/soong/.temp/merged_fs_configpguSgp.txt \ (FS_CONFIG)
		-B system.map \ (BLOCK_LIST_FILE)
		-L / \ (LABEL)
		-i 2891 \ (INODES)
		-M 0 \ (RESERVED_PERCENT)
		-U 4729639d-b5f2-5cc1-a120-9ac5f788683c \ (MKE2FS_UUID)
		-S fd77d4fd-bb91-5ef5-9533-d5d806da85a3 \ (MKE2FS_HASH_SEED)
		-c \ (ext4 share dup blocks)
		--inode_size 256 \ (INODE_SIZE)
		file_contexts.bin
```

mkuserimg_mke2fs 的帮助信息

```bash
$ mkuserimg_mke2fs --help
usage: mkuserimg_mke2fs [-h] [--android_sparse] [--journal_size JOURNAL_SIZE]
                        [--timestamp TIMESTAMP] [--fs_config FS_CONFIG]
                        [--product_out PRODUCT_OUT]
                        [--block_list_file BLOCK_LIST_FILE]
                        [--base_alloc_file_in BASE_ALLOC_FILE_IN]
                        [--base_alloc_file_out BASE_ALLOC_FILE_OUT]
                        [--label LABEL] [--inodes INODES]
                        [--inode_size INODE_SIZE]
                        [--reserved_percent RESERVED_PERCENT]
                        [--flash_erase_block_size FLASH_ERASE_BLOCK_SIZE]
                        [--flash_logical_block_size FLASH_LOGICAL_BLOCK_SIZE]
                        [--mke2fs_uuid MKE2FS_UUID]
                        [--mke2fs_hash_seed MKE2FS_HASH_SEED]
                        [--share_dup_blocks]
                        src_dir output_file {ext2,ext4} mount_point fs_size
                        [file_contexts]

positional arguments:
  src_dir               The source directory for user image.
  output_file           The path of the output image file.
  {ext2,ext4}           Variant of the extended filesystem.
  mount_point           The mount point for user image.
  fs_size               Size of the file system.
  file_contexts         The selinux file context.

optional arguments:
  -h, --help            show this help message and exit
  --android_sparse, -s  Outputs an android sparse image (mke2fs).
  --journal_size JOURNAL_SIZE, -j JOURNAL_SIZE
                        Journal size (mke2fs).
  --timestamp TIMESTAMP, -T TIMESTAMP
                        Fake timetamp for the output image.
  --fs_config FS_CONFIG, -C FS_CONFIG
                        Path to the fs config file (e2fsdroid).
  --product_out PRODUCT_OUT, -D PRODUCT_OUT
                        Path to the directory with device specific fs config
                        files (e2fsdroid).
  --block_list_file BLOCK_LIST_FILE, -B BLOCK_LIST_FILE
                        Path to the block list file (e2fsdroid).
  --base_alloc_file_in BASE_ALLOC_FILE_IN, -d BASE_ALLOC_FILE_IN
                        Path to the input base fs file (e2fsdroid).
  --base_alloc_file_out BASE_ALLOC_FILE_OUT, -A BASE_ALLOC_FILE_OUT
                        Path to the output base fs file (e2fsdroid).
  --label LABEL, -L LABEL
                        The mount point (mke2fs).
  --inodes INODES, -i INODES
                        The extfs inodes count (mke2fs).
  --inode_size INODE_SIZE, -I INODE_SIZE
                        The extfs inode size (mke2fs).
  --reserved_percent RESERVED_PERCENT, -M RESERVED_PERCENT
                        The reserved blocks percentage (mke2fs).
  --flash_erase_block_size FLASH_ERASE_BLOCK_SIZE, -e FLASH_ERASE_BLOCK_SIZE
                        The flash erase block size (mke2fs).
  --flash_logical_block_size FLASH_LOGICAL_BLOCK_SIZE, -o FLASH_LOGICAL_BLOCK_SIZE
                        The flash logical block size (mke2fs).
  --mke2fs_uuid MKE2FS_UUID, -U MKE2FS_UUID
                        The mke2fs uuid (mke2fs) .
  --mke2fs_hash_seed MKE2FS_HASH_SEED, -S MKE2FS_HASH_SEED
                        The mke2fs hash seed (mke2fs).
  --share_dup_blocks, -c
                        ext4 share dup blocks (e2fsdroid).
```



### 1.10 mke2fs

```bash
12:53:04 mkuserimg_mke2fs.py INFO: Running: mke2fs -O ^has_journal -L / -N 2891 -I 256 -M / -m 0 -U 4729639d-b5f2-5cc1-a120-9ac5f788683c -E android_sparse,hash_seed=fd77d4fd-bb91-5ef5-9533-d5d806da85a3 -t ext4 -b 4096 /local/public/users/ygu/android-q-ab2/src-km/out/target/product/inuvik/obj/PACKAGING/target_files_intermediates/inuvik-target_files-eng.rg935739/IMAGES/system.img 274861
12:53:04 mkuserimg_mke2fs.py INFO: Env: {'E2FSPROGS_FAKE_TIME': '1230768000'}
12:53:04 mkuserimg_mke2fs.py INFO: Running: e2fsdroid -T 1230768000 -C /local/public/users/ygu/android-q-ab2/src-km/out/soong/.temp/merged_fs_configpguSgp.txt -B /local/public/users/ygu/android-q-ab2/src-km/out/target/product/inuvik/obj/PACKAGING/target_files_intermediates/inuvik-target_files-eng.rg935739/IMAGES/system.map -s -S /local/public/users/ygu/android-q-ab2/src-km/out/target/product/inuvik/obj/PACKAGING/target_files_intermediates/inuvik-target_files-eng.rg935739/META/file_contexts.bin -f /local/public/users/ygu/android-q-ab2/src-km/out/soong/.temp/tmphevMBR -a / /local/public/users/ygu/android-q-ab2/src-km/out/target/product/inuvik/obj/PACKAGING/target_files_intermediates/inuvik-target_files-eng.rg935739/IMAGES/system.img
```

```bash
$ mke2fs -h
mke2fs: invalid option -- 'h'
Usage: mke2fs [-c|-l filename] [-b block-size] [-C cluster-size]
 [-i bytes-per-inode] [-I inode-size] [-J journal-options]
 [-G flex-group-size] [-N number-of-inodes] [-d root-directory]
 [-m reserved-blocks-percentage] [-o creator-os]
 [-g blocks-per-group] [-L volume-label] [-M last-mounted-directory]
 [-O feature[,...]] [-r fs-revision] [-E extended-option[,...]]
 [-t fs-type] [-T usage-type ] [-U UUID] [-e errors_behavior][-z undo_file]
 [-jnqvDFSV] device [blocks-count]
```



### 1.11 e2fsdroid

```bash
$ e2fsdroid -h
e2fsdroid: invalid option -- 'h'
e2fsdroid [-B block_list] [-D basefs_out] [-T timestamp]
 [-C fs_config] [-S file_contexts] [-p product_out]
 [-a mountpoint] [-d basefs_in] [-f src_dir] [-e] [-s]
 [-u uid-mapping] [-g gid-mapping] image
```





# Android N(7.1) 上系统 image 是如何编译出来的？

## 1. 使用 build_image.py

### 1.1 system.img

```makefile
systemimage_intermediates := \
    $(call intermediates-dir-for,PACKAGING,systemimage)
BUILT_SYSTEMIMAGE := $(systemimage_intermediates)/system.img

# ...

# $(1): output file
define build-systemimage-target
  @echo "Target system fs image: $(1)"
  $(call create-system-vendor-symlink)
  @mkdir -p $(dir $(1)) $(systemimage_intermediates) && rm -rf $(systemimage_intermediates)/system_image_info.txt
  $(call generate-userimage-prop-dictionary, $(systemimage_intermediates)/system_image_info.txt, \
      skip_fsck=true)
  $(hide) PATH=$(foreach p,$(INTERNAL_USERIMAGES_BINARY_PATHS),$(p):)$$PATH \
      ./build/tools/releasetools/build_image.py \
      $(TARGET_OUT) $(systemimage_intermediates)/system_image_info.txt $(1) $(TARGET_OUT) \
      || ( echo "Out of space? the tree size of $(TARGET_OUT) is (MB): " 1>&2 ;\
           du -sm $(TARGET_OUT) 1>&2;\
           if [ "$(INTERNAL_USERIMAGES_EXT_VARIANT)" == "ext4" ]; then \
               maxsize=$(BOARD_SYSTEMIMAGE_PARTITION_SIZE); \
               if [ "$(BOARD_HAS_EXT4_RESERVED_BLOCKS)" == "true" ]; then \
                   maxsize=$$((maxsize - 4096 * 4096)); \
               fi; \
               echo "The max is $$(( maxsize / 1048576 )) MB." 1>&2 ;\
           else \
               echo "The max is $$(( $(BOARD_SYSTEMIMAGE_PARTITION_SIZE) / 1048576 )) MB." 1>&2 ;\
           fi; \
           mkdir -p $(DIST_DIR); cp $(INSTALLED_FILES_FILE) $(DIST_DIR)/installed-files-rescued.txt; \
           exit 1 )
endef

$(BUILT_SYSTEMIMAGE): $(FULL_SYSTEMIMAGE_DEPS) $(INSTALLED_FILES_FILE)
	$(call build-systemimage-target,$@)
```



#### system_image_info.txt

```makefile
# stbszx-bld-6:/public/ygu/android-n-17.1/src
$ find out -type f -iname system_image_info.txt
out/target/product/bcm7268b0usffa4l/obj/PACKAGING/systemimage_intermediates/system_image_info.txt
$ cat out/target/product/bcm7268b0usffa4l/obj/PACKAGING/systemimage_intermediates/system_image_info.txt
fs_type=ext4
system_size=769654784   
system_fs_type=squashfs
system_journal_size=0
system_squashfs_compressor=lz4
userdata_size=5927582720
cache_fs_type=ext4
cache_size=12582912   
extfs_sparse_flag=-s
squashfs_sparse_flag=-s
selinux_fc=out/target/product/bcm7268b0usffa4l/root/file_contexts.bin
boot_signer=false
verity=true
verity_key=build/target/product/security/verity
verity_signer_cmd=verity_signer
verity_fec=true
system_verity_block_device=/dev/block/by-name/system
recovery_as_boot=true
system_root_image=true
ramdisk_dir=out/target/product/bcm7268b0usffa4l/root
skip_fsck=true
```

