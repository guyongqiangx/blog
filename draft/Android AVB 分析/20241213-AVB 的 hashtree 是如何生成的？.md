# AVB 的 hashtree 是如何生成的？

## 1. 前言



```
avbtool add_hashtree_footer \
	--partition_size 886812672 \
	--partition_name system \
	--image system.img \
	--key external/avb/test/data/testkey_rsa2048.pem \
	--algorithm SHA256_RSA2048 \
	--salt 6902f6b436dd8f08a2ecd512d4576a03325e14db8e6b1bb72b68d22f20a6a6d3 \
	--hash_algorithm sha256 \
	--prop com.android.build.system.os_version:13 \
	--prop com.android.build.system.fingerprint:Android/aosp_panther/panther:13/TQ2A.230405.003.E1/rocky12021421:userdebug/test-keys \
	--prop com.android.build.system.security_patch:2023-04-05
```



或者

```bash
```



使用 avbtool 的 `add_hashtree_footer` 操作处理 system.img 或者 vendor.img 时，hashtree 的生成是在 `add_hashtree_footer()` 函数中通过调用 `generate_hash_tree()` 来完成的。



我们看下 `generate_hash_tree()` 函数的具体实现：

> 在线代码：