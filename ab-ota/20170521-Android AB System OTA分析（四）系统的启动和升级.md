# Android A/B System OTA分析（四）系统的启动和升级

Android从7.0开始引入新的OTA升级方式，`A/B System Updates`，这里将其叫做`A/B`系统，涉及的内容较多，分多篇对`A/B`系统的各个方面进行分析。本文为第四篇，系统的启动和升级。

本文基于`AOSP 7.1.1_r23 (NMF27D)`代码进行分析。

## 1. 系统的启动

### 1.1 `bootloader`检查`slot metadata`

系统复位后，`bootloader`会去读取`boot_control`私有的存储数`slot metadata`并进行解析，以此确定从哪一个`slot`启动。
以下是`Android`官方的一个`bootloader`加载流程图：

![`Android`官方`bootloader`加载流程图](https://github.com/guyongqiangx/blog/blob/dev/ab-ota/images/official-ab-updates-state-machine.png?raw=true)

大致启动流程如下：

1. 系统启动后，`bootloader`读取分区元数据`slot metadata`；
2. 检查分区元数据中是否有可启动的分区，如果没有可启动分区，直接进入`bootloader`的`recovery mode`（即`bootloader`下的刷机模式），一般是进入`fastboot`命令行；
3. 如果分区元数据中有可启动的分区，则选择所有可启动分区中优先级最高的`slot`（例如，直接选择当前设置为`active`的分区）；
4. 检查所选择分区的`retry count`（`retry count`表示当前分区可以尝试启动的次数）；
4. 如果当前选择分区的`retry count`为0，且没有启动成功（启动成功的分区会标记为`successful`），则将所选择分区标记为无效分区（通常设置为`unbootable`），然后重复第2步，查找下一个可以启动的分区；
5. 如果当前选择的分区尝试启动次数`retry count`不为0，则表示还可以继续尝试从当前分区启动，需要将其`retry count`进行递减，然后加载相应的`slot`进行启动； 

### 1.2 `linux`系统的启动

上一步中，`bootloader`会根据`slot metadata`确定读取哪一个`slot`的`boot`分区进行启动。

每一个`slot`上有两个`rootfs`：

- `boot`分区自带`recovery mode`的`ramdisk`;
- `system`分区包含了`Android`系统的`rootfs`;

启动中，如何选择加载`boot`分区的`ramdisk`还是`system`分区的`rootfs`呢？
答案是由`kernel`的命令行参数`skip_initramfs`来决定。

下面来看`skip_initramfs`参数是如何起作用的。

系统同时包含`init\noinitramfs.c`和`init\initramfs.c`的代码，并在`initramfs.c`模块中定义并解析`skip_initramfs`参数：

    # init\initramfs.c
	static int __initdata do_skip_initramfs;
	
	static int __init skip_initramfs_param(char *str)
	{
		if (*str)
			return 0;
        # 设置do_skip_initramfs标志
		do_skip_initramfs = 1;
		return 1;
	}
    # 用于解析命令行的`skip_initramfs`参数
	__setup("skip_initramfs", skip_initramfs_param);

如果命令行设置了`skip_initramfs`，则`do_skip_initramfs`会被设置为1。

`linux`调用`populate_rootfs`默认会并加载`boot`分区自带的`ramdisk`，但如果`do_skip_initramfs`被
设置为1，则调用`default_rootfs`生成一个极小的`rootfs`：

	# init\initramfs.c
	static int __init populate_rootfs(void)
	{
		char *err;
	
		# 如果do_skip_initramfs置1，则调用default_rootfs生成一个极小的rootfs
		if (do_skip_initramfs)
			return default_rootfs();
	
	    # 没有设置do_skip_initramfs的情况下，才会解析并加载`boot`分区所包含的`ramdisk`
		err = unpack_to_rootfs(__initramfs_start, __initramfs_size);
		if (err)
			panic("%s", err); /* Failed to decompress INTERNAL initramfs */
		...
		return 0;
	}

`default_rootfs`的内容很简单，用于在内存中生成一个极小的`rootfs`，仅包含`/dev`和`root`两个文件夹以及一个设备节点`/dev/console`：

	# init\noinitramfs.c
	/*
	 * Create a simple rootfs that is similar to the default initramfs
	 */
	static int __init default_rootfs(void)
	{
		int err;
	    # 创建/dev文件夹用于存放/dev/console设备节点
		err = sys_mkdir((const char __user __force *) "/dev", 0755);
		if (err < 0)
			goto out;
	    # 创建/dev/console设备节点
		err = sys_mknod((const char __user __force *) "/dev/console",
				S_IFCHR | S_IRUSR | S_IWUSR,
				new_encode_dev(MKDEV(5, 1)));
		if (err < 0)
			goto out;
	    # 创建/root目录，作为根用户root的home
		err = sys_mkdir((const char __user __force *) "/root", 0700);
		if (err < 0)
			goto out;
	
		return 0;
	
	out:
		printk(KERN_WARNING "Failed to create a rootfs\n");
		return err;
	}

因此`skip_initramfs`参数决定了加载哪一个`rootfs`，进入哪一个系统。

- 加载`android`系统的命令行参数
    `skip_initramfs rootwait ro init=/init root="/dev/dm-0 dm=system none ro,0 1  android-verity <public-key-id> <path-to-system-partition>"`
    例如`Broadcom`的`7252SSFFDR3`参考平台的启动`Android`系统的参数为：

	    mem=1016m@0m mem=1024m@2048m bmem=339m@669m bmem=237m@2048m  \
		brcm_cma=784m@2288m \
		ramoops.mem_address=0x3F800000 ramoops.mem_size=0x800000 ramoops.console_size=0x400000 \
		buildvariant=userdebug \
		veritykeyid=id:7e4333f9bba00adfe0ede979e28ed1920492b40f buildvariant=eng \
		rootwait init=/init ro \
		root=/dev/dm-0 dm="system none ro,0 1 android-verity PARTUUID=c49e0acb-1b38-95e5-548a-2b7260e704a4" skip_initramfs
    除去`rootfs`不相关的参数，看起来是这样的：
    `rootwait init=/init ro root=/dev/dm-0 dm="system none ro,0 1 android-verity PARTUUID=c49e0acb-1b38-95e5-548a-2b7260e704a4" skip_initramfs`

> 命令行中，文件系统的`root`设备由参数`root="/dev/dm-0 dm=system none ro,0 1  android-verity <public-key-id> <path-to-system-partition>"`指定，显然，这里的`root`参数设置将设备名设置为`/dev/dm-0`，至于设备`/dev/dm-0`是一个什么设备，作用为何，属于另一个话题`dm-verity`，此处不再展开讨论。

- 加载`recovery`系统的命令行参数
    `rootwait init=/init ro`
    例如`Broadcom`的`7252SSFFDR3`参考平台的启动`Recovery`的参数为：

	    mem=1016m@0m mem=1024m@2048m bmem=339m@669m bmem=237m@2048m \
		brcm_cma=784m@2288m \
		ramoops.mem_address=0x3F800000 ramoops.mem_size=0x800000 ramoops.console_size=0x400000 \
		rootwait init=/init ro \
		buildvariant=userdebug veritykeyid=id:7e4333f9bba00adfe0ede979e28ed1920492b40f buildvariant=eng
    除去`rootfs`不相关的参数，看起来是这样的：
    `rootwait init=/init ro`

> 默认`linux`是不支持参数`skip_initramfs`参数的，`Android`系统中为了跳过`boot`分区的`ramdisk`，引入了这个命令行参数，参考以下提交：
>
> [https://android-review.googlesource.com/#/c/158491/ [initramfs: Add skip_initramfs command line option]](https://android-review.googlesource.com/#/c/158491/)

### 1.3 `Android`系统的启动

`linux`启动后，通过`dm-verify`机制校验`system`分区，完成后加载`system`分区内包含的`rootfs`，通过`/init`程序解析`/init.rc`脚本，完成`Android`系统的启动。

这部分的启动过程跟传统的系统启动是一样的。

### 1.4 `Recovery`系统的启动

`linux`启动后，根据参数，加载`boot`分区的`ramdisk`，通过`/init`程序解析`/init.rc`脚本，启动`Recovery`系统。

这部分的启动过程跟传统的`Recovery`系统启动是一样的。

## 2. 系统的升级

`A/B`系统升级包的制作方式跟传统系统升级包制作方式基本一致，主要分为两步：

1. 编译系统文件
2. 制作升级包

升级方式根据升级包的内容分为两种：

1. 完整升级，升级包包含完整的系统，对内容进行全新升级；
2. 增量升级/差分升级，升级包仅包含跟当前系统不一样的内容，对系统进行打补丁式升级；

### 2.1 完整升级

1. 升级包的制作

  - 第一步，编译系统

			$ source build/envsetup.sh
			$ lunch bcm7252ssffdr4-userdebug
			$ mkdir dist_output
			$ make -j32 dist DIST_DIR=dist_output
			  [...]
			$ ls -lh dist-output/*target_files*
			-rw-r--r-- 1 ygu users 566M May 21 14:49 bcm7252ssffdr4-target_files-eng.ygu.zip

  - 第二步，制作安装包

			$ ./build/tools/releasetools/ota_from_target_files dist-output/bcm7252ssffdr4-target_files-eng.ygu.zip full-ota.zip
			$ ls -lh dist-output
			-rw-r--r-- 1 ygu users 270M May 21 14:51 full-ota.zip

2. 升级包的内容

    解压缩`full-ota.zip`可以看到其内容：

		$ mkdir full-ota
		$ unzip full-ota.zip -d full-ota
		Archive:  full-ota.zip
		signed by SignApk
		 extracting: full-ota/payload.bin    
		  inflating: full-ota/META-INF/com/android/metadata  
		  inflating: full-ota/care_map.txt   
		  inflating: full-ota/payload_properties.txt  
		  inflating: full-ota/META-INF/com/android/otacert  
		  inflating: full-ota/META-INF/MANIFEST.MF  
		  inflating: full-ota/META-INF/CERT.SF  
		  inflating: full-ota/META-INF/CERT.RSA  
		$ ls -lh full-ota
		total 270M
		drwxr-sr-x 3 ygu users 4.0K May 21 18:14 META-INF
		-rw-r--r-- 1 ygu users   36 Jan  1  2009 care_map.txt
		-rw-r--r-- 1 ygu users 270M Jan  1  2009 payload.bin
		-rw-r--r-- 1 ygu users  154 Jan  1  2009 payload_properties.txt
		$ tree -l full-ota
		full-ota
		|-- META-INF
		|   |-- CERT.RSA
		|   |-- CERT.SF
		|   |-- MANIFEST.MF
		|   `-- com
		|       `-- android
		|           |-- metadata
		|           `-- otacert
		|-- care_map.txt
		|-- payload.bin
		`-- payload_properties.txt
		
		3 directories, 8 files
	其中，`payload.bin`是系统要更新的数据文件，`payload_properties.txt`包含了升级内容的一些属性信息，如下：

		$ cat full-ota/payload_properties.txt 
		FILE_HASH=ozGgyQEcnkI5ZaX+Wbjo5I/PCR7PEZka9fGd0nWa+oY=
		FILE_SIZE=282164983
		METADATA_HASH=GLIKfE6KRwylWMHsNadG/Q8iy5f7ENWTatvMdBlpoPg=
		METADATA_SIZE=21023
	升级时会使用到`payload_properties.txt`里面的信息。

3. 系统包的使用

    `A/B`系统在`debug`模式下会包含升级应用`update_engine_client`，其参数如下：

		bcm7252ssffdr4:/ # which update_engine_client
		/system/bin/update_engine_client
		bcm7252ssffdr4:/ # update_engine_client --help 
		Android Update Engine Client
		
		  --cancel  (Cancel the ongoing update and exit.)  type: bool  default: false
		  --follow  (Follow status update changes until a final state is reached. Exit status is 0 if the update succeeded, and 1 otherwise.)  type: bool  default: false
		  --headers  (A list of key-value pairs, one element of the list per line. Used when --update is passed.)  type: string  default: ""
		  --help  (Show this help message)  type: bool  default: false
		  --offset  (The offset in the payload where the CrAU update starts. Used when --update is passed.)  type: int64  default: 0
		  --payload  (The URI to the update payload to use.)  type: string  default: "http://127.0.0.1:8080/payload"
		  --reset_status  (Reset an already applied update and exit.)  type: bool  default: false
		  --resume  (Resume a suspended update.)  type: bool  default: false
		  --size  (The size of the CrAU part of the payload. If 0 is passed, it will be autodetected. Used when --update is passed.)  type: int64  default: 0
		  --suspend  (Suspend an ongoing update and exit.)  type: bool  default: false
		  --update  (Start a new update, if no update in progress.)  type: bool  default: false

	将`payload.bin`文件放到可以通过`http`访问的地方，然后在命令行调用`update_engine_client`进行升级：

		bcm7252ssffdr4:/ # update_engine_client \
		--payload=http://stbszx-bld-5/public/android/full-ota/payload.bin \
		--update \
		--headers="
		  FILE_HASH=ozGgyQEcnkI5ZaX+Wbjo5I/PCR7PEZka9fGd0nWa+oY= 
		  FILE_SIZE=282164983
		  METADATA_HASH=GLIKfE6KRwylWMHsNadG/Q8iy5f7ENWTatvMdBlpoPg= 
		  METADATA_SIZE=21023 
		"
	其中`headers`选项需要填写`payload_properties.txt`文件的内容。
	
	[2019/08/13]补充一点，这里`update_engine_client`的`--headers=`参数最终是按行进行拆分提取的，所以需要将`--headers=`的每个参数分别写到一行上，然后全部参数用双引号包含，否则可能会出现无法正常解析headers参数导致无法正常执行的情况。

### 2.2 增量升级/差分升级

差分包升级与完整包升级除了升级包的制作不一样之外，生成的升级包文件内容一样，使用`update_engine_client`进行升级的操作也完全一样，因此这里仅说明差分包的制作。

差分升级包的制作

  - 第一步，对`android`进行改动并编译系统

    差分升级时，需要保留原有系统的生成文件，然后修改后生成新的系统文件，这里假定原有系统生成文件位于：dist_output，修改后生成的系统文件位于dist_output-new，编译方式跟完整包的生成方式一样。

		$ source build/envsetup.sh
		$ lunch bcm7252ssffdr4-userdebug
		$ mkdir dist_output
		$ make -j32 dist DIST_DIR=dist_output
		  [...]
		$ ls -lh dist-output-new/*target_files*
		-rw-r--r-- 1 ygu users 566M May 21 15:27 bcm7252ssffdr4-target_files-eng.ygu.zip

  - 第二步，制作安装包

	对比原有系统文件和修改后的系统文件生成差分包，这里通过`-i`指定差分包生成的基线（`baseline`）。

		$./build/tools/releasetools/ota_from_target_files \
		-i dist-output/bcm7252ssffdr4-target_files-eng.ygu.zip \
		dist-output-new/bcm7252ssffdr4-target_files-eng.ygu.zip \
		incremental-ota.zip

### 2.3 升级日志样本

  调用`update_engine_client`进行升级后可以通过`logcat`查看其升级日志，如：

	bcm7252ssffdr4:/ # update_engine_client \
	--payload=http://stbszx-bld-5/public/android/full-ota/payload.bin \
	--update \
	--headers="\
	  FILE_HASH=ozGgyQEcnkI5ZaX+Wbjo5I/PCR7PEZka9fGd0nWa+oY= 
	  FILE_SIZE=282164983 
	  METADATA_HASH=GLIKfE6KRwylWMHsNadG/Q8iy5f7ENWTatvMdBlpoPg= 
	  METADATA_SIZE=21023 
	"
	bcm7252ssffdr4:/ #
	bcm7252ssffdr4:/ # logcat -s update_engine:v
	--------- beginning of main
	--------- beginning of system
	I update_engine: [INFO:main.cc(113)] Chrome OS Update Engine starting
	I update_engine: [INFO:boot_control_android.cc(78)] Loaded boot_control HAL 'boot control hal for bcm platform' version 0.1 authored by 'Broadcom'.
	I update_engine: [INFO:daemon_state_android.cc(43)] Booted in dev mode.
	I update_engine: [INFO:update_attempter_android.cc(199)] Using this install plan:
	I update_engine: [INFO:install_plan.cc(71)] InstallPlan: new_update, payload type: unknown, source_slot: A, target_slot: B, url: http://stbszx-bld-5/public/android/full-ota/payload.bin, payload size: 282164983, payload hash: ozGgyQEcnkI5ZaX+Wbjo5I/PCR7PEZka9fGd0nWa+oY=, metadata size: 21023, metadata signature: , hash_checks_mandatory: true, powerwash_required: false
	W update_engine: [WARNING:hardware_android.cc(126)] STUB: Assuming OOBE is complete.
	I update_engine: [INFO:cpu_limiter.cc(71)] Setting cgroup cpu shares to  2
	E update_engine: [ERROR:utils.cc(199)] 0 == writer.Open(path, O_WRONLY | O_CREAT | O_TRUNC, 0600) failed: No such file or directory
	E update_engine: [ERROR:cpu_limiter.cc(74)] Failed to change cgroup cpu shares to 2 using /sys/fs/cgroup/cpu/update-engine/cpu.shares
	I update_engine: [INFO:update_attempter_android.cc(379)] Marking booted slot as good.
	I update_engine: [INFO:update_attempter_android.cc(394)] Scheduling an action processor start.
	I update_engine: [INFO:action_processor.cc(46)] ActionProcessor: starting InstallPlanAction
	I update_engine: [INFO:action_processor.cc(116)] ActionProcessor: finished InstallPlanAction with code ErrorCode::kSuccess
	I update_engine: [INFO:action_processor.cc(143)] ActionProcessor: starting DownloadAction
	I update_engine: [INFO:install_plan.cc(71)] InstallPlan: new_update, payload type: unknown, source_slot: A, target_slot: B, url: http://stbszx-bld-5/public/android/full-ota/payload.bin, payload size: 282164983, payload hash: ozGgyQEcnkI5ZaX+Wbjo5I/PCR7PEZka9fGd0nWa+oY=, metadata size: 21023, metadata signature: , hash_checks_mandatory: true, powerwash_required: false
	I update_engine: [INFO:download_action.cc(178)] Marking new slot as unbootable
	I update_engine: [INFO:multi_range_http_fetcher.cc(45)] starting first transfer
	I update_engine: [INFO:multi_range_http_fetcher.cc(73)] starting transfer of range 0+282164983
	I update_engine: [INFO:libcurl_http_fetcher.cc(94)] Starting/Resuming transfer
	I update_engine: [INFO:libcurl_http_fetcher.cc(106)] Using proxy: no
	I update_engine: [INFO:libcurl_http_fetcher.cc(237)] Setting up curl options for HTTP
	I update_engine: [INFO:delta_performer.cc(196)] Completed 0/? operations, 14169/282164983 bytes downloaded (0%), overall progress 0%
	I update_engine: [INFO:delta_performer.cc(536)] Manifest size in payload matches expected value from Omaha
	I update_engine: [INFO:delta_performer.cc(1396)] Verifying metadata hash signature using public key: /etc/update_engine/update-payload-key.pub.pem
	I update_engine: [INFO:payload_verifier.cc(93)] signature blob size = 264
	I update_engine: [INFO:payload_verifier.cc(112)] Verified correct signature 1 out of 1 signatures.
	I update_engine: [INFO:delta_performer.cc(1439)] Metadata hash signature matches value in Omaha response.
	I update_engine: [INFO:delta_performer.cc(1459)] Detected a 'full' payload.
	I update_engine: [INFO:delta_performer.cc(374)] PartitionInfo old boot sha256:  size: 0
	I update_engine: [INFO:delta_performer.cc(374)] PartitionInfo new boot sha256: dZpLY9KsQYa2B14B0oBzfUKxVFIH7ocbgT70JavheSc= size: 19480576
	I update_engine: [INFO:delta_performer.cc(374)] PartitionInfo old system sha256:  size: 0
	I update_engine: [INFO:delta_performer.cc(374)] PartitionInfo new system sha256: kFXbYzaM47PifNjuL+Plz1zTMEp1MoajOuXZuCh9yw0= size: 769654784
	I update_engine: [INFO:delta_performer.cc(359)] Applying 10 operations to partition "boot"
	I update_engine: [INFO:delta_performer.cc(647)] Starting to apply update payload operations
	I update_engine: [INFO:delta_performer.cc(359)] Applying 367 operations to partition "system"
	I update_engine: [INFO:delta_performer.cc(196)] Completed 23/377 operations (6%), 40302425/282164983 bytes downloaded (14%), overall progress 10%
	I update_engine: [INFO:delta_performer.cc(196)] Completed 48/377 operations (12%), 79017817/282164983 bytes downloaded (28%), overall progress 20%
	I update_engine: [INFO:delta_performer.cc(196)] Completed 74/377 operations (19%), 118519641/282164983 bytes downloaded (42%), overall progress 30%
	I update_engine: [INFO:delta_performer.cc(196)] Completed 98/377 operations (25%), 158021465/282164983 bytes downloaded (56%), overall progress 40%
	I update_engine: [INFO:delta_performer.cc(196)] Completed 121/377 operations (32%), 192001881/282164983 bytes downloaded (68%), overall progress 50%
	I update_engine: [INFO:delta_performer.cc(196)] Completed 145/377 operations (38%), 231389017/282164983 bytes downloaded (82%), overall progress 60%
	I update_engine: [INFO:delta_performer.cc(196)] Completed 171/377 operations (45%), 270890841/282164983 bytes downloaded (96%), overall progress 70%
	I update_engine: [INFO:delta_performer.cc(196)] Completed 242/377 operations (64%), 273413977/282164983 bytes downloaded (96%), overall progress 80%
	I update_engine: [INFO:delta_performer.cc(196)] Completed 317/377 operations (84%), 273430361/282164983 bytes downloaded (96%), overall progress 90%
	I update_engine: [INFO:delta_performer.cc(196)] Completed 377/377 operations (100%), 282164983/282164983 bytes downloaded (100%), overall progress 100%
	I update_engine: [INFO:delta_performer.cc(1336)] Extracted signature data of size 264 at 282143432
	I update_engine: [INFO:multi_range_http_fetcher.cc(111)] terminating transfer
	I update_engine: [INFO:multi_range_http_fetcher.cc(171)] Received transfer terminated.
	I update_engine: [INFO:multi_range_http_fetcher.cc(123)] TransferEnded w/ code 206
	I update_engine: [INFO:multi_range_http_fetcher.cc(157)] Done w/ all transfers
	I update_engine: [INFO:delta_performer.cc(1596)] Verifying payload using public key: /etc/update_engine/update-payload-key.pub.pem
	I update_engine: [INFO:payload_verifier.cc(93)] signature blob size = 264
	I update_engine: [INFO:payload_verifier.cc(112)] Verified correct signature 1 out of 1 signatures.
	I update_engine: [INFO:delta_performer.cc(1633)] Payload hash matches value in payload.
	I update_engine: [INFO:action_processor.cc(116)] ActionProcessor: finished DownloadAction with code ErrorCode::kSuccess
	I update_engine: [INFO:action_processor.cc(143)] ActionProcessor: starting FilesystemVerifierAction
	I update_engine: [INFO:filesystem_verifier_action.cc(157)] Hashing partition 0 (boot) on device /dev/block/by-name/boot_e
	I update_engine: [INFO:filesystem_verifier_action.cc(248)] Hash of boot: dZpLY9KsQYa2B14B0oBzfUKxVFIH7ocbgT70JavheSc=
	I update_engine: [INFO:filesystem_verifier_action.cc(157)] Hashing partition 1 (system) on device /dev/block/by-name/system_e
	I update_engine: [INFO:filesystem_verifier_action.cc(248)] Hash of system: kFXbYzaM47PifNjuL+Plz1zTMEp1MoajOuXZuCh9yw0=
	I update_engine: [INFO:action_processor.cc(116)] ActionProcessor: finished FilesystemVerifierAction with code ErrorCode::kSuccess
	I update_engine: [INFO:action_processor.cc(143)] ActionProcessor: starting PostinstallRunnerAction
	I update_engine: [INFO:postinstall_runner_action.cc(341)] All post-install commands succeeded
	I update_engine: [INFO:action_processor.cc(116)] ActionProcessor: finished last action PostinstallRunnerAction with code ErrorCode::kSuccess
	I update_engine: [INFO:update_attempter_android.cc(282)] Processing Done.
	I update_engine: [INFO:update_attempter_android.cc(291)] Update successfully applied, waiting to reboot.

  > 以上logcat信息已经去掉了时间戳，原始的log信息请参考：[update_engine_client log](https://raw.githubusercontent.com/guyongqiangx/blog/dev/ab-ota/logs/20170521-update_engine_client.log)

  `update_engine`更新操作成功后会提示`Update successfully applied, waiting to reboot.`，要求系统进行重启，重启后会设置相应分区`slot`的属性为`successful`，表明系统能够成功启动。

  重启系统，检查`Android`系统的编译版本和时间戳，验证升级是否成功。