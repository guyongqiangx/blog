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

> 在线代码：https://xrefandroid.com/android-13.0.0_r83/xref/external/avb/avbtool.py#generate_hash_tree



这里将完整的代码注释如下：

```python
def generate_hash_tree(image, image_size, block_size, hash_alg_name, salt,
                       digest_padding, hash_level_offsets, tree_size):
  """Generates a Merkle-tree for a file.

  Arguments:
    image: The image, as a file.
    image_size: The size of the image.
    block_size: The block size, e.g. 4096.
    hash_alg_name: The hash algorithm, e.g. 'sha256' or 'sha1'.
    salt: The salt to use.
    digest_padding: The padding for each digest.
    hash_level_offsets: The offsets from calc_hash_level_offsets().
    tree_size: The size of the tree, in number of bytes.

  Returns:
    A tuple where the first element is the top-level hash as bytes and the
    second element is the hash-tree as bytes.
  """
  hash_ret = bytearray(tree_size)
  hash_src_offset = 0
  hash_src_size = image_size
  level_num = 0

  # If there is only one block, returns the top-level hash directly.
  if hash_src_size == block_size:
    hasher = create_avb_hashtree_hasher(hash_alg_name, salt)
    image.seek(0)
    hasher.update(image.read(block_size))
    return hasher.digest(), bytes(hash_ret)

  while hash_src_size > block_size:
    level_output_list = []
    remaining = hash_src_size
    while remaining > 0:
      hasher = create_avb_hashtree_hasher(hash_alg_name, salt)
      # Only read from the file for the first level - for subsequent
      # levels, access the array we're building.
      if level_num == 0:
        image.seek(hash_src_offset + hash_src_size - remaining)
        data = image.read(min(remaining, block_size))
      else:
        offset = hash_level_offsets[level_num - 1] + hash_src_size - remaining
        data = hash_ret[offset:offset + block_size]
      hasher.update(data)

      remaining -= len(data)
      if len(data) < block_size:
        hasher.update(b'\0' * (block_size - len(data)))
      level_output_list.append(hasher.digest())
      if digest_padding > 0:
        level_output_list.append(b'\0' * digest_padding)

    level_output = b''.join(level_output_list)

    padding_needed = (round_to_multiple(
        len(level_output), block_size) - len(level_output))
    level_output += b'\0' * padding_needed

    # Copy level-output into resulting tree.
    offset = hash_level_offsets[level_num]
    hash_ret[offset:offset + len(level_output)] = level_output

    # Continue on to the next level.
    hash_src_size = len(level_output)
    level_num += 1

  hasher = create_avb_hashtree_hasher(hash_alg_name, salt)
  hasher.update(level_output)
  return hasher.digest(), bytes(hash_ret)
```

