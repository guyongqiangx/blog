# Android A/B System OTA分析（二）系统image的生成

Android从7.0开始引入新的OTA升级方式，`A/B System Updates`，这里将其叫做`A/B`系统，涉及的内容较多，分多篇对`A/B`系统的各个方面进行分析。本文为第二篇，系统image的生成。

> 版权声明：
> 本文为[guyongqiangx](http://blog.csdn.net/guyongqiangx)原创，欢迎转载，请注明出处：</br>
> [Android A/B System OTA分析（二）系统image的生成： http://blog.csdn.net/guyongqiangx/article/details/71516768](http://blog.csdn.net/guyongqiangx/article/details/71516768)

`image`这个词的含义很多，这里指编译后可以烧写到设备的文件，如`boot.img`，`system.img`等，统称为镜像文件吧。

> 我一直觉得将`image`翻译成镜像文件怪怪的，如果有更贴切词汇，请一定要告诉我啊，十分感谢。

本文基于`AOSP 7.1.1_r23 (NMF27D)`代码进行分析。

## 1. `A/B`系统和传统方式下镜像内容的比较

传统OTA方式下：

1. boot.img内有一个boot ramdisk，用于系统启动时加载system.img；
2. recovery.img内有一个recovery ramdisk，作为recovery系统运行的ramdisk；
3. system.img只包含android系统的应用程序和库文件；

`A/B`系统下：

1. system.img除了包含android系统的应用程序和库文件还，另外含有boot ramdisk，相当于传统OTA下boot.img内的ramdisk存放到system.img内了；
2. boot.img内包含的是recovery ramdisk，而不是boot ramdisk。Android系统启动时不再加载boot.img内的ramdisk，而是通过device mapper机制选择system.img内的ramdisk进行加载；
3. 没有recovery.img文件

要想知道系统的各个分区到底有什么东西，跟传统OTA的镜像文件到底有什么区别，需要阅读Makefile，看看每个镜像里面到底打包了哪些文件。

在看系统编译打包文件生成镜像之前，先看看跟`A/B`相关的到底有哪些变量，以及这些变量有什么作用。

## 2. `A/B`系统相关的Makefile变量

这些变量主要有三类：

- `A/B`系统必须定义的变量
	- `AB_OTA_UPDATER := true`
	- `AB_OTA_PARTITIONS := boot system vendor`
	- `BOARD_BUILD_SYSTEM_ROOT_IMAGE := true`
	- `TARGET_NO_RECOVERY := true`
	- `BOARD_USES_RECOVERY_AS_BOOT := true`
	- `PRODUCT_PACKAGES += update_engine update_verifier`

- `A/B`系统可选定义的变量

	- `PRODUCT_PACKAGES_DEBUG += update_engine_client`

- `A/B`系统不能定义的变量

	- `BOARD_RECOVERYIMAGE_PARTITION_SIZE`
	- `BOARD_CACHEIMAGE_PARTITION_SIZE`
	- `BOARD_CACHEIMAGE_FILE_SYSTEM_TYPE`

以下详细说明这些变量。

1. 必须定义的变量

	- `AB_OTA_UPDATER := true`

	    `A/B`系统的主要开关变量，设置后：

		- `recovery`系统内不再具有操作`cache`分区的功能，`bootable\recovery\device.cpp`；
		- `recovery`系统使用不同的方式来解析升级文件，`bootable\recovery\install.cpp`
		- 生成`A/B`系统相关的META文件

	- `AB_OTA_PARTITIONS := boot system vendor`

	    - 将`A/B`系统可升级的分区写入文件`$(zip_root)/META/ab_partitions.txt`

	- `BOARD_BUILD_SYSTEM_ROOT_IMAGE := true`

	    将boot ramdisk放到system分区内

	- `TARGET_NO_RECOVERY := true`

	    不再生成`recovery.img`镜像

	- `BOARD_USES_RECOVERY_AS_BOOT := true`

	    将recovery ramdisk放到boot.img文件内

	- `PRODUCT_PACKAGES += update_engine update_verifier`

	    编译`update_engine`和`update_verifier`模块，并安装相应的应用

2. 可选的变量

	- `PRODUCT_PACKAGES_DEBUG += update_engine_client`

	    系统自带了一个`update_engine_client`应用，可以根据需要选择是否编译并安装

3. 不能定义的变量

	- `BOARD_RECOVERYIMAGE_PARTITION_SIZE`

	    系统没有recovery分区，不需要设置`recovery`分区的`SIZE`

	- `BOARD_CACHEIMAGE_PARTITION_SIZE`

	    系统没有`cache`分区，不需要设置`cache`分区的`SIZE`

	- `BOARD_CACHEIMAGE_FILE_SYSTEM_TYPE`

	    系统没有`cache`分区，不需要设置`cache`分区的`TYPE`

## 3. `A/B`系统镜像文件的生成

`build\core\Makefile`定义了所需生成的镜像目标和规则，各镜像规则如下，我直接在代码里进行注释了。

1. `recovery.img`


		# A/B系统中，"TARGET_NO_RECOVERY := true"，所以条件成立
		ifeq (,$(filter true, $(TARGET_NO_KERNEL) $(TARGET_NO_RECOVERY)))
		INSTALLED_RECOVERYIMAGE_TARGET := $(PRODUCT_OUT)/recovery.img
		else
		INSTALLED_RECOVERYIMAGE_TARGET :=
		endif

	由于`A/B`系统定了`TARGET_NO_RECOVERY := true`，这里`INSTALLED_RECOVERYIMAGE_TARGET`被设置为空，所以不会生成`recovery.img`

2. `boot.img`

		# 定义boot.img的名字和存放的路径
		INSTALLED_BOOTIMAGE_TARGET := $(PRODUCT_OUT)/boot.img

		#
		# 以下error表明：
		#     BOARD_USES_RECOVERY_AS_BOOT和BOARD_BUILD_SYSTEM_ROOT_IMAGE
		#     在A/B系统中需要同时被定义为true
		#
		# BOARD_USES_RECOVERY_AS_BOOT = true must have BOARD_BUILD_SYSTEM_ROOT_IMAGE = true.
        # BOARD_USES_RECOVERY_AS_BOOT 已经定义为true
		ifeq ($(BOARD_USES_RECOVERY_AS_BOOT),true) 
		ifneq ($(BOARD_BUILD_SYSTEM_ROOT_IMAGE),true)
          # 如果没有定义BOARD_BUILD_SYSTEM_ROOT_IMAGE 则编译终止，并显示错误信息
		  $(error BOARD_BUILD_SYSTEM_ROOT_IMAGE must be enabled for BOARD_USES_RECOVERY_AS_BOOT.)
		endif
		endif

		...

		# 好吧，这里才是生成boot.img的地方
		ifeq ($(BOARD_USES_RECOVERY_AS_BOOT),true)
		# 对boot.img添加依赖：boot_signer，这里不关心
		ifeq (true,$(PRODUCTS.$(INTERNAL_PRODUCT).PRODUCT_SUPPORTS_BOOT_SIGNER))
		$(INSTALLED_BOOTIMAGE_TARGET) : $(BOOT_SIGNER)
		endif
		# 对boot.img添加依赖：vboot_signer.sh，这里不关心
		ifeq (true,$(PRODUCTS.$(INTERNAL_PRODUCT).PRODUCT_SUPPORTS_VBOOT))
		$(INSTALLED_BOOTIMAGE_TARGET) : $(VBOOT_SIGNER)
		endif
		# boot.img的其它依赖，并通过宏build-recoveryimage-target来生成boot.img
		$(INSTALLED_BOOTIMAGE_TARGET): $(MKBOOTFS) $(MKBOOTIMG) $(MINIGZIP) \
				$(INSTALLED_RAMDISK_TARGET) \
				$(INTERNAL_RECOVERYIMAGE_FILES) \
				$(recovery_initrc) $(recovery_sepolicy) $(recovery_kernel) \
				$(INSTALLED_2NDBOOTLOADER_TARGET) \
				$(recovery_build_prop) $(recovery_resource_deps) \
				$(recovery_fstab) \
				$(RECOVERY_INSTALL_OTA_KEYS)
				$(call pretty,"Target boot image from recovery: $@")
				$(call build-recoveryimage-target, $@)
		endif

		#
        # 上面的规则中：
        #   INSTALLED_BOOTIMAGE_TARGET = $(PRODUCT_OUT)/boot.img
        # 其依赖的是recovery系统文件，最后通过build-recoveryimage-target打包成boot.img
        # 这不就是把recovery.img换个名字叫boot.img么？
        #

		#
        # 再来看看原本的recovery.img的生成规则：
        #  - A/B 系统下，INSTALLED_RECOVERYIMAGE_TARGET已经定义为空，什么都不做
        #  - 非A/B 系统下，以下规则会生成recovery.img
        #
		$(INSTALLED_RECOVERYIMAGE_TARGET): $(MKBOOTFS) $(MKBOOTIMG) $(MINIGZIP) \
				$(INSTALLED_RAMDISK_TARGET) \
				$(INSTALLED_BOOTIMAGE_TARGET) \
				$(INTERNAL_RECOVERYIMAGE_FILES) \
				$(recovery_initrc) $(recovery_sepolicy) $(recovery_kernel) \
				$(INSTALLED_2NDBOOTLOADER_TARGET) \
				$(recovery_build_prop) $(recovery_resource_deps) \
				$(recovery_fstab) \
				$(RECOVERY_INSTALL_OTA_KEYS)
				$(call build-recoveryimage-target, $@)

    对比`A/B`系统下`boot.img`生成方式和非`A/B`系统下`recovery.img`的生成方式，基本上是一样的，所以`A/B`系统下的`boot.img`相当于非`A/B`系统下的`recovery.img`。

3. `system.img`

		#
		# build-systemimage-target宏函数定义
		#     宏函数内部调用build_image.py，从$(TARGET_OUT)目录，即$(PRODUCT_OUT)/system目录创建镜像文件
		# 
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

		#
		# 调用build-systemimage-target，生成目标文件$(BUILT_SYSTEMIMAGE)
		# 即：obj\PACKAGING\systemimage_intermediates\system.img文件
		# 
		$(BUILT_SYSTEMIMAGE): $(FULL_SYSTEMIMAGE_DEPS) $(INSTALLED_FILES_FILE)
            # 站住，生成system.img的入口就在这里了
			$(call build-systemimage-target,$@)

		# 定义system.img的名字和存放的路径
		INSTALLED_SYSTEMIMAGE := $(PRODUCT_OUT)/system.img
		SYSTEMIMAGE_SOURCE_DIR := $(TARGET_OUT)

		...

	看完这段代码我开始有点崩溃了~~
	此前boot.img里面的ramdisk是recovery系统的recovery ramdisk，这里生成system.img也不见哪里添加了ramdisk啊，那系统启动时用recovery的ramdisk挂载system分区么？显然不是啊~~那boot ramdisk到底藏到哪里去了啊？

	木有了办法，那就老老实实看看宏`build-systemimage-target`的过程吧，调用命令：

	- 第一步，调用`$(call create-system-vendor-symlink)`创建符号链接
	- 第二步，创建文件夹`$(systemimage_intermediates)`，并删除其中的文件`system_image_info.txt`
	- 第三步，调用`call generate-userimage-prop-dictionary`，重新生成系统属性文件`system_image_info.txt`
	- 第四步，调用`build_image.py`，根据系统属性文件`system_image_info.txt`和`system`目录`$(PRODUCT_OUT)/system`创建`system.img`文件
	
	显然重点就在第四步了，看看`build_image.py`到底是如何生成`system.img`的。

	`build_image.py`的主程序比较简单：

	- 脚本入口

			# 运行build_image.py脚本的入口，转到main函数
			if __name__ == '__main__':
			  main(sys.argv[1:])

	- 主程序`main`函数

			# 主程序
			def main(argv):
			  if len(argv) != 4:
			    print __doc__
			    sys.exit(1)
			
			  """
	           * build_image.py的调用命令为：
	           * ./build/tools/releasetools/build_image.py \
		       *     $(TARGET_OUT) \
		       *     $(systemimage_intermediates)/system_image_info.txt \
		       *     $(systemimage_intermediates)/system.img \
		       *     $(TARGET_OUT)
		       *
	          """
			  in_dir = argv[0]           # 参数0：in_dir=$(TARGET_OUT)
			  glob_dict_file = argv[1]   # 参数1：glob_dict_file=$(systemimage_intermediates)/system_image_info.txt
			  out_file = argv[2]         # 参数2：outfile=$(systemimage_intermediates)/system.img
			  target_out = argv[3]       # 参数3：target_out=$(TARGET_OUT)
			
	          # 解析系统属性的字典文件system_image_info.txt
			  glob_dict = LoadGlobalDict(glob_dict_file)
			  if "mount_point" in glob_dict:
			    # The caller knows the mount point and provides a dictionay needed by
			    # BuildImage().
			    image_properties = glob_dict
			  else:
			    image_filename = os.path.basename(out_file)
			    mount_point = ""
	            # 设置system.img的挂载点为system
			    if image_filename == "system.img":
			      mount_point = "system"
			    ...
			    else:
			      print >> sys.stderr, "error: unknown image file name ", image_filename
			      exit(1)
			
			    image_properties = ImagePropFromGlobalDict(glob_dict, mount_point)
	
	          # 调用BuildImage函数来创建文件
			  if not BuildImage(in_dir, image_properties, out_file, target_out):
			    print >> sys.stderr, "error: failed to build %s from %s" % (out_file,
			                                                                in_dir)
			    exit(1)

	- `BuildImage`函数

			def BuildImage(in_dir, prop_dict, out_file, target_out=None):
			  ...

			  # 关键！！！前面改动过了in_dir，所以条件成立
			  if in_dir != origin_in:
			    # Construct a staging directory of the root file system.
			    ramdisk_dir = prop_dict.get("ramdisk_dir")
			    if ramdisk_dir:
			      shutil.rmtree(in_dir)
                  # 将字典system_image_info.txt里"ramdisk_dir"指定的内容复制到临时文件夹in_dir中，并保持原有的符号链接
			      shutil.copytree(ramdisk_dir, in_dir, symlinks=True)
			    staging_system = os.path.join(in_dir, "system")
                # 删除in_dir/system目录，即删除ramdisk_dir下system目录
			    shutil.rmtree(staging_system, ignore_errors=True)
                # 将origin_in目录的内容复制到ramdisk_dir/system目录下
                # 原来的origin_in是指定的$(PRODUCT_OUT)/system目录
                # 所以这里的操作是将ramdisk和system的内容合并生成一个完整的文件系统
			    shutil.copytree(origin_in, staging_system, symlinks=True)
			
			  reserved_blocks = prop_dict.get("has_ext4_reserved_blocks") == "true"
			  ext4fs_output = None

              # 继续对合并后完整的文件系统进行其它操作，最后打包为system.img
			  ...
			
			  return exit_code == 0

		显然，`build_image.py`脚本将ramdisk和system文件夹下的内容合并成一个完整的文件系统，最终输出为system.img，再也不用担心system.img没有rootfs了。

4. `userdata.img`

		# Don't build userdata.img if it's extfs but no partition size
		skip_userdata.img :=
		# 如果TARGET_USERIMAGES_USE_EXT4定义为true，则会进行以下定义：
        # INTERNAL_USERIMAGES_USE_EXT := true
        # INTERNAL_USERIMAGES_EXT_VARIANT := ext4
        # 在vendor相关的deivce下，BoradConfig.mk中会定义BOARD_USERDATAIMAGE_PARTITION_SIZE
        # 所以这里最终skip_userdata.img仍然为空
		ifdef INTERNAL_USERIMAGES_EXT_VARIANT
		ifndef BOARD_USERDATAIMAGE_PARTITION_SIZE
		skip_userdata.img := true
		endif
		endif
		
        # skip_userdata.img为空，所以这里会定义userdata.img并生成这个文件
		ifneq ($(skip_userdata.img),true)
		userdataimage_intermediates := \
		    $(call intermediates-dir-for,PACKAGING,userdata)
		BUILT_USERDATAIMAGE_TARGET := $(PRODUCT_OUT)/userdata.img
		
        # 具体生成userdata.img的宏函数
		define build-userdataimage-target
		  $(call pretty,"Target userdata fs image: $(INSTALLED_USERDATAIMAGE_TARGET)")
		  @mkdir -p $(TARGET_OUT_DATA)
		  @mkdir -p $(userdataimage_intermediates) && rm -rf $(userdataimage_intermediates)/userdata_image_info.txt
		  $(call generate-userimage-prop-dictionary, $(userdataimage_intermediates)/userdata_image_info.txt, skip_fsck=true)
		  $(hide) PATH=$(foreach p,$(INTERNAL_USERIMAGES_BINARY_PATHS),$(p):)$$PATH \
		      ./build/tools/releasetools/build_image.py \
		      $(TARGET_OUT_DATA) $(userdataimage_intermediates)/userdata_image_info.txt $(INSTALLED_USERDATAIMAGE_TARGET) $(TARGET_OUT)
		  $(hide) $(call assert-max-image-size,$(INSTALLED_USERDATAIMAGE_TARGET),$(BOARD_USERDATAIMAGE_PARTITION_SIZE))
		endef

        # 好吧，这里才是真正调用build-userdataimage-target去生成userdata.img的规则
		# We just build this directly to the install location.
		INSTALLED_USERDATAIMAGE_TARGET := $(BUILT_USERDATAIMAGE_TARGET)
		$(INSTALLED_USERDATAIMAGE_TARGET): $(INTERNAL_USERIMAGES_DEPS) \
		                                   $(INTERNAL_USERDATAIMAGE_FILES)
            # 生成userdata.img的入口就这里了
			$(build-userdataimage-target)


	这里的步骤跟生成system.img基本一致，宏函数`build-userdataimage-target`内通过`build_image.py`来将`$(PRODUCT_OUT)/data`目录内容打包生成`userdata.img`，不同的是，这里不再需要放入`ramdisk`的内容。

    显然，userdata.img的生成跟是否是`A/B`系统没有关系。

5. `cache.img`

		# cache partition image
	    # `A/B`系统中 BOARD_CACHEIMAGE_FILE_SYSTEM_TYPE 没有定义，这里条件不能满足，所以不会生成cache.img
		ifdef BOARD_CACHEIMAGE_FILE_SYSTEM_TYPE
		INTERNAL_CACHEIMAGE_FILES := \
		    $(filter $(TARGET_OUT_CACHE)/%,$(ALL_DEFAULT_INSTALLED_MODULES))
		
		cacheimage_intermediates := \
		    $(call intermediates-dir-for,PACKAGING,cache)
		BUILT_CACHEIMAGE_TARGET := $(PRODUCT_OUT)/cache.img
		
		...

		# We just build this directly to the install location.
        # 这里是真正去生成cache.img的地方，可惜`A/B`系统下不会再有调用了
		INSTALLED_CACHEIMAGE_TARGET := $(BUILT_CACHEIMAGE_TARGET)
		$(INSTALLED_CACHEIMAGE_TARGET): $(INTERNAL_USERIMAGES_DEPS) $(INTERNAL_CACHEIMAGE_FILES)
			$(build-cacheimage-target)
		
		...

		else # BOARD_CACHEIMAGE_FILE_SYSTEM_TYPE
		# we need to ignore the broken cache link when doing the rsync
		IGNORE_CACHE_LINK := --exclude=cache
		endif # BOARD_CACHEIMAGE_FILE_SYSTEM_TYPE

	于A/B系统定了没有定义`BOARD_CACHEIMAGE_FILE_SYSTEM_TYPE`，这里`BUILT_CACHEIMAGE_TARGET`也不会定义，所以不会生成cache.img

6. `vendor.img`

		# vendor partition image
        # 如果系统内有定义BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE，则这里会生成vendor.img
		ifdef BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE
        # 定义vendor系统内包含的所有文件
		INTERNAL_VENDORIMAGE_FILES := \
		    $(filter $(TARGET_OUT_VENDOR)/%,\
		      $(ALL_DEFAULT_INSTALLED_MODULES)\
		      $(ALL_PDK_FUSION_FILES))
		
		# platform.zip depends on $(INTERNAL_VENDORIMAGE_FILES).
		$(INSTALLED_PLATFORM_ZIP) : $(INTERNAL_VENDORIMAGE_FILES)
		
        # vendor的文件列表：installed-files-vendor.txt
		INSTALLED_FILES_FILE_VENDOR := $(PRODUCT_OUT)/installed-files-vendor.txt
		$(INSTALLED_FILES_FILE_VENDOR) : $(INTERNAL_VENDORIMAGE_FILES)
			@echo Installed file list: $@
			@mkdir -p $(dir $@)
			@rm -f $@
			$(hide) build/tools/fileslist.py $(TARGET_OUT_VENDOR) > $@
		
        # vendor.img目标
		vendorimage_intermediates := \
		    $(call intermediates-dir-for,PACKAGING,vendor)
		BUILT_VENDORIMAGE_TARGET := $(PRODUCT_OUT)/vendor.img
		
        # 定义生成vendor.img的宏函数build-vendorimage-target
		define build-vendorimage-target
		  $(call pretty,"Target vendor fs image: $(INSTALLED_VENDORIMAGE_TARGET)")
		  @mkdir -p $(TARGET_OUT_VENDOR)
		  @mkdir -p $(vendorimage_intermediates) && rm -rf $(vendorimage_intermediates)/vendor_image_info.txt
		  $(call generate-userimage-prop-dictionary, $(vendorimage_intermediates)/vendor_image_info.txt, skip_fsck=true)
		  $(hide) PATH=$(foreach p,$(INTERNAL_USERIMAGES_BINARY_PATHS),$(p):)$$PATH \
		      ./build/tools/releasetools/build_image.py \
		      $(TARGET_OUT_VENDOR) $(vendorimage_intermediates)/vendor_image_info.txt $(INSTALLED_VENDORIMAGE_TARGET) $(TARGET_OUT)
		  $(hide) $(call assert-max-image-size,$(INSTALLED_VENDORIMAGE_TARGET),$(BOARD_VENDORIMAGE_PARTITION_SIZE))
		endef
		
		# We just build this directly to the install location.
        # 生成vendor.img的依赖和规则
		INSTALLED_VENDORIMAGE_TARGET := $(BUILT_VENDORIMAGE_TARGET)
		$(INSTALLED_VENDORIMAGE_TARGET): $(INTERNAL_USERIMAGES_DEPS) $(INTERNAL_VENDORIMAGE_FILES) $(INSTALLED_FILES_FILE_VENDOR)
			$(build-vendorimage-target)
		
		.PHONY: vendorimage-nodeps
		vendorimage-nodeps: | $(INTERNAL_USERIMAGES_DEPS)
			$(build-vendorimage-target)
		
        # 如果定义了BOARD_PREBUILT_VENDORIMAGE，说明已经预备好了vendor.img，那就直接复制到目标位置
		else ifdef BOARD_PREBUILT_VENDORIMAGE
		INSTALLED_VENDORIMAGE_TARGET := $(PRODUCT_OUT)/vendor.img
		$(eval $(call copy-one-file,$(BOARD_PREBUILT_VENDORIMAGE),$(INSTALLED_VENDORIMAGE_TARGET)))
		endif

	显然，vendor.img跟是否是`A/B`系统没有关系，主要看系统是否定义了`BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE`。

到此为止，我们已经分析了除升级包`update.zip`外的主要文件的生成，包括`recovery.img`，`boot.img`，`system.img`，`userdata.img`，`cache.img`和`vendor.img`。

总结：

- `recovery.img`，不再单独生成，传统方式的`recovery.img`现在叫做`boot.img`
- `boot.img`，包含`kernel`和`recovery`模式的`ramdisk`
- `system.img`，传统方式下`system.img`由`$(PRODUCT_OUT)/system`文件夹打包而成，`A/B`系统下，制作时将`$(PRODUCT_OUT)/root`和`$(PRODUCT_OUT)/system`合并到一起，生成一个完整的带有`rootfs`的`system.img`
- `userdata.img`，跟原来一样，打包`$(PRODUCT_OUT)/data`文件夹而成
- `cache.img`，`A/B`系统下不再单独生成`cache.img`
- `vendor.img`，文件的生成跟是否`A/B`系统无关，主要有厂家决定

现在的情况是，设备启动后`bootloader`解析`boot.img`得到`kernel`文件，启动`linux`进入系统，然后加载`Android`主系统`system`，但是`boot.img`和`system.img`两个镜像内都有`rootfs`，这个启动是如何启动，那这个到底是怎么搞的呢？下一篇会对这个启动流程详细分析。