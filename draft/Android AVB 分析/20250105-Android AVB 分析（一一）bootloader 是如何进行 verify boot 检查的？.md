# 20250105-Android AVB 分析（一一）bootloader 是如何进行 verify boot 检查的？

上一篇[《Android AVB 分析（十）AVB 有哪些相关的源码？》](https://blog.csdn.net/guyongqiangx/article/details/144936814)中分析了 AVB 源码结构，本篇正式深入 AVB 源码，看看在 bootloader 中是如何使用 libavb 进行 verify boot 检查验证的。



对于 bootloader 中的启动验证，这一块属于厂家自己的代码，因为各个厂家的 bootloader 都可能不一样, 有的用 u-boot，有的基于 UEFI，有的可能是私有的 bootloader。而 Android 官方只要求集成 libavb 完成验证即可。



## 2. u-boot 中的 verify boot 命令

没有办法公开分享不开源的 bootloader 源码，只能以公开的 u-boot 源码进行分析，看看 u-boot 中是如何使用 libavb 进行启动验证的。

> 本文基于写作时最新的 u-boot 源码进行分析: v2025.01-rc6
>
> - https://github.com/u-boot/u-boot/tree/v2025.01-rc6
>
> 并参考 u-boot 关于 AVB 2.0 的参考文档:
>
> - https://docs.u-boot.org/en/latest/android/avb2.html

虽然是基于 u-boot 最新的源码分析，但实际上 u-boot 中集成的 libavb 库并不是最新的 v1.3 版，而是 v1.1 版本。

```c
u-boot-v2025.01$ grep -n AVB_VERSION_MAJOR -C 2 lib/libavb/avb_version.h
18-
19-/* The version number of AVB - keep in sync with avbtool. */
20:#define AVB_VERSION_MAJOR 1
21-#define AVB_VERSION_MINOR 1
22-#define AVB_VERSION_SUB 0
```

所以本文基于 u-boot 中的 libavb v1.1 版本的代码进行分析。

后面看情况再决定是否跟踪分析 libavb v1.1, v1.2 和 v1.3 版本的变更。



### 2.1 AVB 相关命令

根据 u-boot 文档介绍，集成 AVB 2.0 时，提供了以下命令：

```bash
avb init <dev> - initialize avb 2 for <dev>
avb read_rb <num> - read rollback index at location <num>
avb write_rb <num> <rb> - write rollback index <rb> to <num>
avb is_unlocked - returns unlock status of the device
avb get_uuid <partname> - read and print uuid of partition <part>
avb read_part <partname> <offset> <num> <addr> - read <num> bytes from
    partition <partname> to buffer <addr>
avb read_part_hex <partname> <offset> <num> - read <num> bytes from
    partition <partname> and print to stdout
avb write_part <partname> <offset> <num> <addr> - write <num> bytes to
    <partname> by <offset> using data from <addr>
avb read_pvalue <name> <bytes> - read a persistent value <name>
avb write_pvalue <name> <value> - write a persistent value <name>
avb verify [slot_suffix] - run verification process using hash data
    from vbmeta structure
    [slot_suffix] - _a, _b, etc (if vbmeta partition is slotted)
```

对于没有 A/B  槽位(slot)的系统，验证 Verify Boot，执行如下命令:

```bash
=> avb init 1
=> avb verify
```

对于有 Android A/B 系统存在两个槽位(a/b)的情况，执行如下命令验证指定的槽位：

```bash
=> avb init 1
=> avb verify _a
```

### 2.2 命令 `avb init`

对于 `avb init` 命令，实际上调用的是 `do_avb_init`函数：

```c
static struct cmd_tbl cmd_avb[] = {
	U_BOOT_CMD_MKENT(init, 2, 0, do_avb_init, "", ""),
	U_BOOT_CMD_MKENT(read_rb, 2, 0, do_avb_read_rb, "", ""),
	U_BOOT_CMD_MKENT(write_rb, 3, 0, do_avb_write_rb, "", ""),
	U_BOOT_CMD_MKENT(is_unlocked, 1, 0, do_avb_is_unlocked, "", ""),
	U_BOOT_CMD_MKENT(get_uuid, 2, 0, do_avb_get_uuid, "", ""),
	U_BOOT_CMD_MKENT(read_part, 5, 0, do_avb_read_part, "", ""),
	U_BOOT_CMD_MKENT(read_part_hex, 4, 0, do_avb_read_part_hex, "", ""),
	U_BOOT_CMD_MKENT(write_part, 5, 0, do_avb_write_part, "", ""),
	U_BOOT_CMD_MKENT(verify, 2, 0, do_avb_verify_part, "", ""),
#ifdef CONFIG_OPTEE_TA_AVB
	U_BOOT_CMD_MKENT(read_pvalue, 3, 0, do_avb_read_pvalue, "", ""),
	U_BOOT_CMD_MKENT(write_pvalue, 3, 0, do_avb_write_pvalue, "", ""),
#endif
};
```



在 `do_avb_init()` 内部进一步调用 `avb_ops_alloc()` 来设置 libavb 库需要的 AvbOps:

```c
int do_avb_init(struct cmd_tbl *cmdtp, int flag, int argc, char *const argv[])
{
	unsigned long mmc_dev;

	if (argc != 2)
		return CMD_RET_USAGE;

	mmc_dev = hextoul(argv[1], NULL);

	if (avb_ops)
		avb_ops_free(avb_ops);

	avb_ops = avb_ops_alloc(mmc_dev);
	if (avb_ops)
		return CMD_RET_SUCCESS;
	else
		printf("Can't allocate AvbOps");

	printf("Failed to initialize AVB\n");

	return CMD_RET_FAILURE;
}
```



`avb_ops_alloc()` 用于初始化 AvbOps，后续所有 IO 操作都通过 AvbOps 来执行。

```c
/**
 * ============================================================================
 * AVB2.0 AvbOps alloc/initialisation/free
 * ============================================================================
 */
AvbOps *avb_ops_alloc(int boot_device)
{
	struct AvbOpsData *ops_data;

	ops_data = avb_calloc(sizeof(struct AvbOpsData));
	if (!ops_data)
		return NULL;

	ops_data->ops.user_data = ops_data;

	ops_data->ops.read_from_partition = read_from_partition;
	ops_data->ops.write_to_partition = write_to_partition;
	ops_data->ops.validate_vbmeta_public_key = validate_vbmeta_public_key;
	ops_data->ops.read_rollback_index = read_rollback_index;
	ops_data->ops.write_rollback_index = write_rollback_index;
	ops_data->ops.read_is_device_unlocked = read_is_device_unlocked;
	ops_data->ops.get_unique_guid_for_partition =
		get_unique_guid_for_partition;
#ifdef CONFIG_OPTEE_TA_AVB
	ops_data->ops.write_persistent_value = write_persistent_value;
	ops_data->ops.read_persistent_value = read_persistent_value;
#endif
	ops_data->ops.get_size_of_partition = get_size_of_partition;
	ops_data->mmc_dev = boot_device;

	return &ops_data->ops;
}
```



### 2.3 命令 `avb verify`

对于 `avb verify` 命令，实际上调用的是 `do_avb_verify_part()`函数，由于这个函数比较长，这里不再截图，直接贴代码：

```c
int do_avb_verify_part(struct cmd_tbl *cmdtp, int flag,
		       int argc, char *const argv[])
{
	const char * const requested_partitions[] = {"boot", NULL};
	AvbSlotVerifyResult slot_result;
	AvbSlotVerifyData *out_data;
	enum avb_boot_state boot_state;
	char *cmdline;
	char *extra_args;
	char *slot_suffix = "";
	int ret;

	bool unlocked = false;
	int res = CMD_RET_FAILURE;

	if (!avb_ops) {
		printf("AVB is not initialized, please run 'avb init <id>'\n");
		return CMD_RET_FAILURE;
	}

	if (argc < 1 || argc > 2)
		return CMD_RET_USAGE;

	if (argc == 2)
		slot_suffix = argv[1];

	printf("## Android Verified Boot 2.0 version %s\n",
	       avb_version_string());

    /*
     * 1. 获取设备的 unlock 状态
     */
	ret = avb_ops->read_is_device_unlocked(avb_ops, &unlocked);
	if (ret != AVB_IO_RESULT_OK) {
		printf("Can't determine device lock state, err = %d\n",
		       ret);
		return CMD_RET_FAILURE;
	}

    /*
     * 2. 调用 avb_slot_verify() 对 boot 分区进行 verify boot 验证
     */
	slot_result =
		avb_slot_verify(avb_ops,
				requested_partitions,
				slot_suffix,
				unlocked,
				AVB_HASHTREE_ERROR_MODE_RESTART_AND_INVALIDATE,
				&out_data);

	/*
	 * LOCKED devices with custom root of trust setup is not supported (YELLOW)
	 */
	if (slot_result == AVB_SLOT_VERIFY_RESULT_OK) {
		printf("Verification passed successfully\n");

		/*
		 * ORANGE state indicates that device may be freely modified.
		 * Device integrity is left to the user to verify out-of-band.
		 */
		if (unlocked)
			boot_state = AVB_ORANGE;
		else
			boot_state = AVB_GREEN;

		/* export boot state to AVB_BOOTARGS env var */
		extra_args = avb_set_state(avb_ops, boot_state);
		if (extra_args)
			cmdline = append_cmd_line(out_data->cmdline,
						  extra_args);
		else
			cmdline = out_data->cmdline;

		env_set(AVB_BOOTARGS, cmdline);

		res = CMD_RET_SUCCESS;
	} else {
		printf("Verification failed, reason: %s\n", str_avb_slot_error(slot_result));
	}

	if (out_data)
		avb_slot_verify_data_free(out_data);

	return res;
}
```



## 3. avb_slot_verify 函数

从前面的分析看到，如果在命令行调用 `avb verify _a`，则会以下面的参数调用 `avb_slot_verify()` 函数：

```c
slot_result =
    avb_slot_verify(avb_ops,
            requested_partitions, /* {"boot", NULL} */
            slot_suffix,          /* "_a" */
            unlocked,             /* locked: false; unlocked: true */
            AVB_HASHTREE_ERROR_MODE_RESTART_AND_INVALIDATE,
            &out_data);
```

对于函数 `avb_slot_verify()` ，函数的定义如下：

```c
AvbSlotVerifyResult avb_slot_verify(AvbOps* ops,
                                    const char* const* requested_partitions,
                                    const char* ab_suffix,
                                    AvbSlotVerifyFlags flags,
                                    AvbHashtreeErrorMode hashtree_error_mode,
                                    AvbSlotVerifyData** out_data);
```

其头文件`avb_slot_verify.h`中关于函数的注释就是非常好的说明文档。

我这里将这部分注释用 AI 翻译成中文，供参考：

> avb_slot_verify() 函数执行对由 |ab_suffix| 标识的 slot 的完整验证，并加载和验证分区内容，这些分区的名称在以 NULL 结尾的字符串数组|requested_partitions| 中（每个分区必须使用哈希验证）。如果不使用 A/B，传入一个空字符串（例如 ""，而不是 NULL）作为 |ab_suffix|。该参数必须包含下划线前缀，例如，使用 "_a" 表示第一个 slot。
>
> 通常，|requested_partitions| 数组仅包含一个用于 boot 分区的条目，即 'boot'。
>
> 验证包括从 'vbmeta'、请求的哈希分区以及可能的其他分区（附加 |ab_suffix|）加载并验证数据，检查回滚索引，并验证用于签名数据的公钥是否被接受。完成这些操作时会使用 |ops| 中的函数。
>
> 如果 |out_data| 不为 NULL，它将被设置为一个新分配的 |AvbSlotVerifyData| 结构，该结构包含实际引导 slot 所需的所有数据。在完成使用后，应使用 avb_slot_verify_data_free() 释放该数据结构。
> 请参阅以下内容以了解何时返回此结构。
>
> |flags| 参数用于影响 avb_slot_verify() 的语义，例如，可以使用AVB_SLOT_VERIFY_FLAGS_ALLOW_VERIFICATION_ERROR 标志忽略验证错误，这是在解锁状态（UNLOCKED state）下需要的功能。有关详细信息，请参阅 AvbSlotVerifyFlags 枚举。
>
> |hashtree_error_mode| 参数应设置为所需的错误处理模式。有关详细信息，请参阅 AvbHashtreeErrorMode 枚举。
>
> 另外请注意，如果返回 AVB_SLOT_VERIFY_RESULT_ERROR_OOM、AVB_SLOT_VERIFY_RESULT_ERROR_IO 或AVB_SLOT_VERIFY_RESULT_ERROR_INVALID_METADATA，则不会设置 |out_data|。
>
> 如果一切验证正确且所有公钥都被接受，将返回 AVB_SLOT_VERIFY_RESULT_OK。
>
> 如果一切验证正确，但一个或多个公钥未被接受（包括完整性数据未签名的情况），将返回 AVB_SLOT_VERIFY_RESULT_ERROR_PUBLIC_KEY_REJECTED。
>
> 如果无法分配内存，将返回 AVB_SLOT_VERIFY_RESULT_ERROR_OOM。
>
> 如果在加载数据或获取回滚索引时发生 I/O 错误，将返回 AVB_SLOT_VERIFY_RESULT_ERROR_IO。
>
> 如果数据验证失败，例如摘要不匹配或签名检查失败，将返回 AVB_SLOT_VERIFY_RESULT_ERROR_VERIFICATION。
>
> 如果回滚索引小于其存储值，将返回 AVB_SLOT_VERIFY_RESULT_ERROR_ROLLBACK_INDEX。
>
> 如果某些元数据无效或不一致，将返回 AVB_SLOT_VERIFY_RESULT_ERROR_INVALID_METADATA。
>
> 如果某些元数据需要比当前使用的 libavb 更新的版本，将返回 AVB_SLOT_VERIFY_RESULT_ERROR_UNSUPPORTED_VERSION。
>
> 如果调用者传递了无效参数，例如尝试在未启用 AVB_SLOT_VERIFY_FLAGS_ALLOW_VERIFICATION_ERROR 的情况下使用 AVB_HASHTREE_ERROR_MODE_LOGGING，将返回 AVB_SLOT_VERIFY_RESULT_ERROR_INVALID_ARGUMENT。

以下是对 `avb_slot_verify()`函数的详细注释:

```c
AvbSlotVerifyResult avb_slot_verify(AvbOps* ops,
                                    const char* const* requested_partitions,
                                    const char* ab_suffix,
                                    AvbSlotVerifyFlags flags,
                                    AvbHashtreeErrorMode hashtree_error_mode,
                                    AvbSlotVerifyData** out_data) {
  /*
   * 1. 初始化变量，进行参数检查，给必要的数据结构分配内存
   */
  // 初始化返回结果为无效参数错误
  AvbSlotVerifyResult ret = AVB_SLOT_VERIFY_RESULT_ERROR_INVALID_ARGUMENT;
  // 初始化 slot_data 为 NULL
  AvbSlotVerifyData* slot_data = NULL;
  // 初始化算法类型为无
  AvbAlgorithmType algorithm_type = AVB_ALGORITHM_TYPE_NONE;
  // 初始化使用 boot 作为 vbmeta 的标志为 false
  bool using_boot_for_vbmeta = false;
  // 定义顶层 vbmeta 的头部
  AvbVBMetaImageHeader toplevel_vbmeta;
  // 检查是否允许验证错误
  bool allow_verification_error =
      (flags & AVB_SLOT_VERIFY_FLAGS_ALLOW_VERIFICATION_ERROR);
  // 初始化额外命令行替换列表为 NULL
  AvbCmdlineSubstList* additional_cmdline_subst = NULL;

  // 提前失败，如果缺少用于槽验证的 AvbOps
  avb_assert(ops->read_is_device_unlocked != NULL);
  avb_assert(ops->read_from_partition != NULL);
  avb_assert(ops->get_size_of_partition != NULL);
  avb_assert(ops->read_rollback_index != NULL);
  avb_assert(ops->get_unique_guid_for_partition != NULL);

  // 如果 out_data 不为 NULL，将其初始化为 NULL
  if (out_data != NULL) {
    *out_data = NULL;
  }

  // 如果允许 dm-verity 错误，则仅在设置为允许验证错误时才允许
  if (hashtree_error_mode == AVB_HASHTREE_ERROR_MODE_LOGGING &&
      !allow_verification_error) {
    ret = AVB_SLOT_VERIFY_RESULT_ERROR_INVALID_ARGUMENT;
    goto fail;
  }

  // 确保在请求 libavb 管理 verity 状态时，传入的 AvbOps 支持持久值
  if (hashtree_error_mode == AVB_HASHTREE_ERROR_MODE_MANAGED_RESTART_AND_EIO) {
    if (ops->read_persistent_value == NULL ||
        ops->write_persistent_value == NULL) {
      avb_error(
          "Persistent values required for "
          "AVB_HASHTREE_ERROR_MODE_MANAGED_RESTART_AND_EIO "
          "but are not implemented in given AvbOps.\n");
      ret = AVB_SLOT_VERIFY_RESULT_ERROR_INVALID_ARGUMENT;
      goto fail;
    }
  }

  // 确保在不使用 vbmeta 分区时，传入的 AvbOps 支持验证公钥和获取回滚索引位置
  if (flags & AVB_SLOT_VERIFY_FLAGS_NO_VBMETA_PARTITION) {
    if (ops->validate_public_key_for_partition == NULL) {
      avb_error(
          "AVB_SLOT_VERIFY_FLAGS_NO_VBMETA_PARTITION was passed but the "
          "validate_public_key_for_partition() operation isn't implemented.\n");
      ret = AVB_SLOT_VERIFY_RESULT_ERROR_INVALID_ARGUMENT;
      goto fail;
    }
  } else {
    avb_assert(ops->validate_vbmeta_public_key != NULL);
  }

  // 为 slot_data 分配内存
  slot_data = avb_calloc(sizeof(AvbSlotVerifyData));
  if (slot_data == NULL) {
    ret = AVB_SLOT_VERIFY_RESULT_ERROR_OOM;
    goto fail;
  }
  // 为 vbmeta_images 分配内存
  slot_data->vbmeta_images =
      avb_calloc(sizeof(AvbVBMetaData) * MAX_NUMBER_OF_VBMETA_IMAGES);
  if (slot_data->vbmeta_images == NULL) {
    ret = AVB_SLOT_VERIFY_RESULT_ERROR_OOM;
    goto fail;
  }
  // 为 loaded_partitions 分配内存
  slot_data->loaded_partitions =
      avb_calloc(sizeof(AvbPartitionData) * MAX_NUMBER_OF_LOADED_PARTITIONS);
  if (slot_data->loaded_partitions == NULL) {
    ret = AVB_SLOT_VERIFY_RESULT_ERROR_OOM;
    goto fail;
  }

  // 创建新的命令行替换列表
  additional_cmdline_subst = avb_new_cmdline_subst_list();
  if (additional_cmdline_subst == NULL) {
    ret = AVB_SLOT_VERIFY_RESULT_ERROR_OOM;
    goto fail;
  }

  /*
   * 2. 加载并验证 vbmeta 分区数据
   *    如果 flags 标明没有 vbmeta 分区，则遍历验证 requested_partitions 列表分区的 vbmeta 数据
   */
  // 如果没有 vbmeta 分区，遍历 requested_partitions 列表中的每一个分区
  if (flags & AVB_SLOT_VERIFY_FLAGS_NO_VBMETA_PARTITION) {
    if (requested_partitions == NULL || requested_partitions[0] == NULL) {
      avb_fatal(
          "Requested partitions cannot be empty when using "
          "AVB_SLOT_VERIFY_FLAGS_NO_VBMETA_PARTITION");
      ret = AVB_SLOT_VERIFY_RESULT_ERROR_INVALID_ARGUMENT;
      goto fail;
    }

    // 如果无 vbmeta 分区，单独加载并验证处理 requested_partitions 列表中的每一个分区
    // 例如：{"boot", "vendor_boot", NULL}
    for (size_t n = 0; requested_partitions[n] != NULL; n++) {
      ret = load_and_verify_vbmeta(ops,
                                   requested_partitions,
                                   ab_suffix,
                                   flags,
                                   allow_verification_error,
                                   0 /* toplevel_vbmeta_flags */,
                                   0 /* rollback_index_location */,
                                   requested_partitions[n],
                                   avb_strlen(requested_partitions[n]),
                                   NULL /* expected_public_key */,
                                   0 /* expected_public_key_length */,
                                   slot_data,
                                   &algorithm_type,
                                   additional_cmdline_subst);
      if (!allow_verification_error && ret != AVB_SLOT_VERIFY_RESULT_OK) {
        goto fail;
      }
    }
  } else {
    // 正常路径，加载并验证 "vbmeta" 分区
    ret = load_and_verify_vbmeta(ops,
                                 requested_partitions,
                                 ab_suffix,
                                 flags,
                                 allow_verification_error,
                                 0 /* toplevel_vbmeta_flags */,
                                 0 /* rollback_index_location */,
                                 "vbmeta",
                                 avb_strlen("vbmeta"),
                                 NULL /* expected_public_key */,
                                 0 /* expected_public_key_length */,
                                 slot_data,
                                 &algorithm_type,
                                 additional_cmdline_subst);
    if (!allow_verification_error && ret != AVB_SLOT_VERIFY_RESULT_OK) {
      goto fail;
    }
  }

  // 根据检查结果判断，如果结果不应继续，则失败
  if (!result_should_continue(ret)) {
    goto fail;
  }

  // 如果验证成功，检查是否使用了 boot 分区进行验证
  if (!(flags & AVB_SLOT_VERIFY_FLAGS_NO_VBMETA_PARTITION)) {
    if (avb_strcmp(slot_data->vbmeta_images[0].partition_name, "vbmeta") != 0) {
      avb_assert(
          avb_strcmp(slot_data->vbmeta_images[0].partition_name, "boot") == 0);
      using_boot_for_vbmeta = true;
    }
  }

  // 字节交换顶层 vbmeta 头部，因为后面会用到
  avb_vbmeta_image_header_to_host_byte_order(
      (const AvbVBMetaImageHeader*)slot_data->vbmeta_images[0].vbmeta_data,
      &toplevel_vbmeta);

  // 填充返回结果的 |ab_suffix| 字段
  slot_data->ab_suffix = avb_strdup(ab_suffix);
  if (slot_data->ab_suffix == NULL) {
    ret = AVB_SLOT_VERIFY_RESULT_ERROR_OOM;
    goto fail;
  }

  // 如果禁用验证，我们就完成了...我们特别不想添加任何 androidboot.* 选项，因为禁用了验证
  if (toplevel_vbmeta.flags & AVB_VBMETA_IMAGE_FLAGS_VERIFICATION_DISABLED) {
    // 由于禁用了验证，我们没有处理任何描述符，因此没有 cmdline...所以设置 root= 以便挂载系统分区
    avb_assert(slot_data->cmdline == NULL);
    // 具有动态分区的设备将没有系统分区。相反，它有一个大的超级分区来容纳 *.img 文件。详见 b/119551429。
    if (has_system_partition(ops, ab_suffix)) {
      slot_data->cmdline =
          avb_strdup("root=PARTUUID=$(ANDROID_SYSTEM_PARTUUID)");
    } else {
      // |cmdline| 字段应为 NUL 终止的字符串。
      slot_data->cmdline = avb_strdup("");
    }
    if (slot_data->cmdline == NULL) {
      ret = AVB_SLOT_VERIFY_RESULT_ERROR_OOM;
      goto fail;
    }
  } else {
    // 如果请求，管理 dm-verity 模式
    AvbHashtreeErrorMode resolved_hashtree_error_mode = hashtree_error_mode;
    if (hashtree_error_mode ==
        AVB_HASHTREE_ERROR_MODE_MANAGED_RESTART_AND_EIO) {
      AvbIOResult io_ret;
      io_ret = avb_manage_hashtree_error_mode(
          ops, flags, slot_data, &resolved_hashtree_error_mode);
      if (io_ret != AVB_IO_RESULT_OK) {
        ret = AVB_SLOT_VERIFY_RESULT_ERROR_IO;
        if (io_ret == AVB_IO_RESULT_ERROR_OOM) {
          ret = AVB_SLOT_VERIFY_RESULT_ERROR_OOM;
        }
        goto fail;
      }
    }
    slot_data->resolved_hashtree_error_mode = resolved_hashtree_error_mode;

    // 添加选项
    AvbSlotVerifyResult sub_ret;
    sub_ret = avb_append_options(ops,
                                 flags,
                                 slot_data,
                                 &toplevel_vbmeta,
                                 algorithm_type,
                                 hashtree_error_mode,
                                 resolved_hashtree_error_mode);
    if (sub_ret != AVB_SLOT_VERIFY_RESULT_OK) {
      ret = sub_ret;
      goto fail;
    }
  }

  // 替换 $(ANDROID_SYSTEM_PARTUUID) 和相关内容
  if (slot_data->cmdline != NULL && avb_strlen(slot_data->cmdline) != 0) {
    char* new_cmdline;
    new_cmdline = avb_sub_cmdline(ops,
                                  slot_data->cmdline,
                                  ab_suffix,
                                  using_boot_for_vbmeta,
                                  additional_cmdline_subst);
    if (new_cmdline != slot_data->cmdline) {
      if (new_cmdline == NULL) {
        ret = AVB_SLOT_VERIFY_RESULT_ERROR_OOM;
        goto fail;
      }
      avb_free(slot_data->cmdline);
      slot_data->cmdline = new_cmdline;
    }
  }

  // 如果 out_data 不为 NULL，将 slot_data 赋值给 out_data
  if (out_data != NULL) {
    *out_data = slot_data;
  } else {
    avb_slot_verify_data_free(slot_data);
  }

  // 释放命令行替换列表
  avb_free_cmdline_subst_list(additional_cmdline_subst);
  additional_cmdline_subst = NULL;

  // 如果不允许验证错误，断言返回结果为 OK
  if (!allow_verification_error) {
    avb_assert(ret == AVB_SLOT_VERIFY_RESULT_OK);
  }

  return ret;

// 失败处理
fail:
  if (slot_data != NULL) {
    avb_slot_verify_data_free(slot_data);
  }
  if (additional_cmdline_subst != NULL) {
    avb_free_cmdline_subst_list(additional_cmdline_subst);
  }
  return ret;
}
```

总结一下，Android Verified Boot (AVB) 的核心验证函数的 `avb_verify_slot()` 做了以下操作：

1. 初始化和参数检查，给必要的数据结构分配内存
2. 加载并验证 vbmeta 分区数据
   - 根据标志决定是否使用 vbmeta 分区。
   - 如果没有 vbmeta 分区，根据请求的分区表，遍历分区进行加载和验证。
   - 如果有 vbmeta 分区，加载和验证 "vbmeta" 分区。
3. 处理设备解锁和验证禁用的情况
4. 管理 dm-verity 的错误处理模式
5. 构建和处理内核命令行参数, 替换命令行中的变量。
6. 返回验证结果



## 4. load_and_verify_vbmeta 函数

我们看到，在 `avb_slot_verify()` 函数中，vbmeta 分区或其它如 boot 分区的 vbmeta 数据验证是交由 `load_and_verify_vbmeta()` 函数来完成的。

