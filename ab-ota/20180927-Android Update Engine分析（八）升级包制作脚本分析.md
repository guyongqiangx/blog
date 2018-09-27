# Android Update Engine分析（八）升级包制作脚本分析

本系列到现在为止共有七篇，分别如下:

- [Android Update Engine分析（一）Makefile](https://blog.csdn.net/guyongqiangx/article/details/77650362)
- [Android Update Engine分析（二）Protobuf和AIDL文件](https://blog.csdn.net/guyongqiangx/article/details/80819901)
- [Android Update Engine分析（三）客户端进程](https://blog.csdn.net/guyongqiangx/article/details/80820399)
- [Android Update Engine分析（四）服务端进程](https://blog.csdn.net/guyongqiangx/article/details/82116213)
- [Android Update Engine分析（五）服务端核心之Action机制](https://blog.csdn.net/guyongqiangx/article/details/82226079)
- [Android Update Engine分析（六）服务端核心之Action详解](https://blog.csdn.net/guyongqiangx/article/details/82390015)
- [Android Update Engine分析（七） DownloadAction之FileWriter](https://blog.csdn.net/guyongqiangx/article/details/82805813)

前面几篇分别分析了Update Engine的Makefile，客户端demo进程和服务端，基本了解了Update Engine关于升级是如何运作的。而在升级之前，需要先制作升级包。升级包的制作和使用升级包进行升级是两个相反的过程，理解了升级包数据是如何产生的，反过来有利于我们理解Update Engine升级过程中的一些行为。所以我们将从差分包的制作命令开始，跟踪分析整个差分升级包的制作流程，看看升级数据到底是如何生成的。

一直以来，`ota_from_target_files`脚本负责Android系统升级包的制作，不论是传统的升级方式还是A/B系统的升级方式。

在A/B系统中，`ota_from_target_files`会将升级包制作的流程分解，并将payload文件制作和更新的操作转交给`brillo_update_payload`脚本处理，而后者会进一步调用可执行文件`delta_generator`去生成或更新用于升级的payload数据。因此，整个升级包的制作分为三个层次，顶层为`ota_from_target_files`，接下来是`brillo_update_payload`，最底层是`delta_generator`。为避免文章太长，本文主要分析脚本`ota_from_target_files`和`brillo_update_payload`的行为，下一篇将对`delta_generator`的代码进行详细分析。

> 本文涉及的Android代码版本：android‐7.1.1_r23 (NMF27D)

为了方便阅读，以下为本篇目录，只想了解特定内容请点击相应链接跳转：
- [1. 如何制作升级包？](#1)
- [2. 脚本`ota_from_target_files`](#2)
  - [2.1 脚本入口](#2.1)
  - [2.2 `main`函数](#2.2)
  - [2.3 `WriteABOTAPackageWithBrilloScript`函数](#2.3)
  - [2.4 脚本`ota_from_target_files`总结](#2.4)
- [3. 脚本`brillo_update_payload`](#3)
  - [3.1 生成payload文件](#3.1)
    - [`cmd_generate()`函数](#cmd_generate)
    - [`extract_image()`函数](#extract_image)
    - [`extract_image_brillo()`函数](#extract_image_brillo)
    - [生成payload文件总结](#payload_sumary)
  - [3.2 生成payload数据和metadata数据的哈希值](#3.2)
  - [3.3 将payload签名和metadata签名写回payload文件](#3.3)
  - [3.4 提取payload文件的properties数据](#3.4)
  - [3.5 脚本brillo_update_payload总结](#3.5)

## <span id="1">1. 如何制作升级包？</span>

[《Android A/B System OTA分析（四）系统的启动和升级》](https://blog.csdn.net/guyongqiangx/article/details/72604355)一文中提到了全量升级包和增量升级包的制作方式，主要有两步：

1. 编译系统
2. 制作升级包

如果是做全量升级包，则只需要编译一次系统，在此系统的基础上制作升级文件；

如果是做增量升级包，则需要先编译一遍系统保存起来，修改代码，再编译一遍系统。然后工具基于这里的新旧两个系统制作升级包。

以下是我在该篇文章中使用的命令：
```
#
# 编译系统
#

$ source build/envsetup.sh
$ lunch bcm7252ssffdr4-userdebug
$ mkdir dist_output
$ make -j32 dist DIST_DIR=dist_output
  [...]
$ ls -lh dist-output/*target_files*
-rw-r--r-- 1 ygu users 566M May 21 14:49 bcm7252ssffdr4-target_files-eng.ygu.zip

#
# 制作全量升级包
#

$ ./build/tools/releasetools/ota_from_target_files \
    dist-output/bcm7252ssffdr4-target_files-eng.ygu.zip \
    full-ota.zip

# 
# 制作增量升级包
#

$./build/tools/releasetools/ota_from_target_files \
    -i dist-output/bcm7252ssffdr4-target_files-eng.ygu.zip \
    dist-output-new/bcm7252ssffdr4-target_files-eng.ygu.zip \
    incremental-ota.zip
```

## <span id="2">2. 脚本`ota_from_target_files`</span>

假设系统修改前后编译生成的ota包分别叫做old.zip和new.zip，生成的差分升级包叫做update.zip。

差分包制作脚本`ota_from_target_files`位于目录：`build/tools/releasetools`。

本篇以差分升级包的制作为例，执行命令:
```
android-7.1.1_r23$ ./build/tools/releasetools/ota_from_target_files \
    -i dist/old.zip dist/new.zip \
    dist/update.zip
```
然后跟踪代码执行路径来分析差分包是如何生成的。

### <span id="2.1">2.1 脚本入口</span>

差分包制作命令的入口点在`ota_from_target_files.py`脚本的`if __name__ == '__main__'`语句:
```
if __name__ == '__main__':
  try:
    common.CloseInheritedPipes()

    # main函数接收到的参数 sys.argv: [
    # './build/tools/releasetools/ota_from_target_files', 
    # '-i', 
    # 'dist/old.zip', 
    # 'dist/new.zip', 
    # 'dist/update.zip'
    # ]
    main(sys.argv[1:])
  except common.ExternalError as e:
    print
    print "   ERROR: %s" % (e,)
    print
    sys.exit(1)
  finally:
    common.Cleanup()
```

这里会将除脚本名称外的参数传递到函数`main(sys.argv[1:])`去执行。

### <span id="2.2">2.2 `main`函数</span>

`main`函数接收命令行传递过来的参数，并进行处理：

```
def main(argv):

  # 这里定义了option参数的处理函数option_handler, 略过函数细节
  def option_handler(o, a):
    ...
    return True

  # 对传入的参数argv调用common.ParseOptions进行解析
  # 解析后的结果：
  # args = ['dist/new.zip', 'dist/update.zip']
  # OPTIONS.incremental_source = dist/old.zip
  args = common.ParseOptions(argv, __doc__,
                             extra_opts="b:k:i:d:wne:t:a:2o:",
                             extra_long_opts=[
                                 "board_config=",
                                 "package_key=",
                                 "incremental_from=",
                                 "full_radio",
                                 "full_bootloader",
                                 "wipe_user_data",
                                 "no_prereq",
                                 "downgrade",
                                 "extra_script=",
                                 "worker_threads=",
                                 "aslr_mode=",
                                 "two_step",
                                 "no_signing",
                                 "block",
                                 "binary=",
                                 "oem_settings=",
                                 "oem_no_mount",
                                 "verify",
                                 "no_fallback_to_full",
                                 "stash_threshold=",
                                 "gen_verify",
                                 "log_diff=",
                                 "payload_signer=",
                                 "payload_signer_args=",
                             ], extra_option_handler=option_handler)

  if len(args) != 2:
    common.Usage(__doc__)
    sys.exit(1)

  # 没有指定downgrade参数，略过
  if OPTIONS.downgrade:
    # Sanity check to enforce a data wipe.
    if not OPTIONS.wipe_user_data:
      raise ValueError("Cannot downgrade without a data wipe")

    # We should only allow downgrading incrementals (as opposed to full).
    # Otherwise the device may go back from arbitrary build with this full
    # OTA package.
    if OPTIONS.incremental_source is None:
      raise ValueError("Cannot generate downgradable full OTAs - consider"
                       "using --omit_prereq?")

  # 加载args[0](即'dist/new.zip')中指定词典文件的键值(key/value)对信息, 
  # LoadInfoDict('dist/new.zip')函数中读取的文件包括：
  # 1. META/misc_info.txt
  # 2. BOOT/RAMDISK/etc/recovery.fstab
  # 3. SYSTEM/build.prop
  # 
  # Load the dict file from the zip directly to have a peek at the OTA type.
  # For packages using A/B update, unzipping is not needed.
  input_zip = zipfile.ZipFile(args[0], "r")
  OPTIONS.info_dict = common.LoadInfoDict(input_zip)
  common.ZipClose(input_zip)

  # 检查是否A/B系统, 读取到的 info_dict['ab_update'] = (str) true
  ab_update = OPTIONS.info_dict.get("ab_update") == "true"

  # 当前的A/B系统走这里
  if ab_update:
    # 前面解析参数时得到：OPTIONS.incremental_source = dist/old.zip
    if OPTIONS.incremental_source is not None:
      # 从'dist/new.zip'加载的key/value信息作为target_info_dict
      OPTIONS.target_info_dict = OPTIONS.info_dict
      
      # 从'dist/old.zip'加载的key/value信息作为source_info_dict
      source_zip = zipfile.ZipFile(OPTIONS.incremental_source, "r")
      OPTIONS.source_info_dict = common.LoadInfoDict(source_zip)
      common.ZipClose(source_zip)

    # 如果在命令行中添加了'-v'选项，则这里打印获取到的key/value信息
    if OPTIONS.verbose:
      print "--- target info ---"
      common.DumpInfoDict(OPTIONS.info_dict)

      if OPTIONS.incremental_source is not None:
        print "--- source info ---"
        common.DumpInfoDict(OPTIONS.source_info_dict)

    # 所有生成A/B系统payload.bin的操作都由这里的调用搞定
    # target_file='dist/new.zip'
    # output_file='dist/update.zip'
    # source_file='dist/old.zip'
    WriteABOTAPackageWithBrilloScript(
        target_file=args[0],
        output_file=args[1],
        source_file=OPTIONS.incremental_source)

    print "done."
    return
```

`main()`函数的操作比较简单，先解析命令行参数，然后根据参数读取target包的相关词典文件信息，提取key/value键值对。如果提取到的key/value键值对中，"ab_update"对应的信息为"true"，则说明当前是基于A/B系统制作升级包。如果当前是制作差分包，则还需要提取source包的key/value键值对。

> 关于到底提取了那些key/value信息，可以在命令行添加'-v'选项，这样在执行时会打印所有target和source的键值对: 
> ```
> android-7.1.1_r23$ ./build/tools/releasetools/ota_from_target_files \ 
>   -v -i dist/old.zip dist/new.zip \ 
>   dist/update.zip
> ```

完成键值对的提取后，调用`WriteABOTAPackageWithBrilloScript()`函数制作升级包，所以剩余的工作都在这个函数里。

### <span id="2.3">2.3 `WriteABOTAPackageWithBrilloScript`函数</span>

```
def WriteABOTAPackageWithBrilloScript(target_file, output_file,
                                      source_file=None):
  """Generate an Android OTA package that has A/B update payload."""

  # 差分包制作命令'ota_from_target_files -i dist/old.zip dist/new.zip dist/update.zip'的传入参数：
  # target_file='dist/new.zip'
  # output_file='dist/update.zip'
  # source_file='dist/old.zip'

  #
  # 设置 OPTIONS.package_key
  #
  # OPTIONS.package_key选项从命令行参数'-k'或'--package_key'解析得到，所以默认情况下为None
  # 在META/misc_info.txt中，'default_system_dev_certificate=build/target/product/security/testkey'
  #
  # Setup signing keys.
  if OPTIONS.package_key is None:
    OPTIONS.package_key = OPTIONS.info_dict.get(
        "default_system_dev_certificate",
        "build/target/product/security/testkey")

  #
  # 设置 OPTIONS.payload_signer
  #
  # OPTIONS.payload_signer选项从命令行参数'--payload_signer'解析得到，所以默认情况下为None
  # 如果没有设置OPTIONS.payload_signer, 这里构造openssl命令基于package_key生成临时的rsa_key：
  # 'openssl pkcs8 -in build/target/product/security/testkey.pk8 -inform DER -nocrypt -out /tmp/key-oQvVbH.key'
  #
  # A/B updater expects a signing key in RSA format. Gets the key ready for
  # later use in step 3, unless a payload_signer has been specified.
  if OPTIONS.payload_signer is None:
    cmd = ["openssl", "pkcs8",
           "-in", OPTIONS.package_key + OPTIONS.private_key_suffix,
           "-inform", "DER", "-nocrypt"]
    rsa_key = common.MakeTempFile(prefix="key-", suffix=".key")
    cmd.extend(["-out", rsa_key])
    p1 = common.Run(cmd, stdout=subprocess.PIPE)
    p1.wait()
    assert p1.returncode == 0, "openssl pkcs8 failed"

  # 准备临时文件，用于output文件的生成
  # Stage the output zip package for package signing.
  temp_zip_file = tempfile.NamedTemporaryFile()
  output_zip = zipfile.ZipFile(temp_zip_file, "w",
                               compression=zipfile.ZIP_DEFLATED)

  # 提取键值对的"oem_fingerprint_properties"信息，默认情况下没有，为None
  # Metadata to comply with Android OTA package format.
  oem_props = OPTIONS.info_dict.get("oem_fingerprint_properties", None)
  oem_dict = None
  if oem_props:
    if OPTIONS.oem_source is None:
      raise common.ExternalError("OEM source required for this build")
    oem_dict = common.LoadDictionaryFromLines(
        open(OPTIONS.oem_source).readlines())

  #
  # 构造 metadata
  # 
  # 从字典信息构建metadata, 我制作升级包时得到的metadata信息为：
  # 'post-build': 'broadcom/bcm72604usff/bcm72604usff:7.1.1/NMF27D/rg935706151800:userdebug/test-keys', 
  # 'post-build-incremental': 'eng.rg9357.20180615.180010', 
  # 'pre-device': 'bcm72604usff'
  # 'post-timestamp': '1529056810', 
  # 'ota-type': 'AB', 
  # 'ota-required-cache': '0'
  #
  metadata = {
      "post-build": CalculateFingerprint(oem_props, oem_dict,
                                         OPTIONS.info_dict),
      "post-build-incremental" : GetBuildProp("ro.build.version.incremental",
                                              OPTIONS.info_dict),
      "pre-device": GetOemProperty("ro.product.device", oem_props, oem_dict,
                                   OPTIONS.info_dict),
      "post-timestamp": GetBuildProp("ro.build.date.utc", OPTIONS.info_dict),
      "ota-required-cache": "0",
      "ota-type": "AB",
  }

  # 制作差分包时，添加相应的pre-build/pre-build-incremental信息：
  # 'pre-build': 'broadcom/bcm72604usff/bcm72604usff:7.1.1/NMF27D/rg935706151800:userdebug/test-keys'
  # 'pre-build-incremental': 'eng.rg9357.20180615.180010', 
  #
  if source_file is not None:
    metadata["pre-build"] = CalculateFingerprint(oem_props, oem_dict,
                                                 OPTIONS.source_info_dict)
    metadata["pre-build-incremental"] = GetBuildProp(
        "ro.build.version.incremental", OPTIONS.source_info_dict)

  #
  # 1. 生成payload文件
  #
  # 构造使用脚本生成payload数据的命令并执行：
  # brillo_update_payload generate --payload /tmp/payload-YqkYe1.bin \
  #                                --target_image dist/new.zip \
  #                                --source_image dist/old.zip
  #
  # 1. Generate payload.
  payload_file = common.MakeTempFile(prefix="payload-", suffix=".bin")
  cmd = ["brillo_update_payload", "generate",
         "--payload", payload_file,
         "--target_image", target_file]
  if source_file is not None:
    cmd.extend(["--source_image", source_file])
  p1 = common.Run(cmd, stdout=subprocess.PIPE)
  p1.wait()
  assert p1.returncode == 0, "brillo_update_payload generate failed"

  #
  # 2. 生成payload和metadata数据的哈希值
  #
  # 构造使用脚本从payload数据生成payload哈希和metadata哈希的命令并执行：
  # brillo_update_payload hash --unsigned_payload /tmp/payload-YqkYe1.bin \
  #                            --signature_size 256 \
  #                            --metadata_hash_file /tmp/sig-LDz25q.bin \
  #                            --payload_hash_file /tmp/sig-Cdhb80.bin
  #
  # 2. Generate hashes of the payload and metadata files.
  payload_sig_file = common.MakeTempFile(prefix="sig-", suffix=".bin")
  metadata_sig_file = common.MakeTempFile(prefix="sig-", suffix=".bin")
  cmd = ["brillo_update_payload", "hash",
         "--unsigned_payload", payload_file,
         "--signature_size", "256",
         "--metadata_hash_file", metadata_sig_file,
         "--payload_hash_file", payload_sig_file]
  p1 = common.Run(cmd, stdout=subprocess.PIPE)
  p1.wait()
  assert p1.returncode == 0, "brillo_update_payload hash failed"

  #
  # 3. 对payload哈希和metadata哈希数据进行签名
  # 

  # 构造用于对payload哈希和metadata哈希签名的文件
  # 'openssl pkcs8 -in build/target/product/security/testkey.pk8 -inform DER -nocrypt -out /tmp/key-oQvVbH.key'
  #
  # 3. Sign the hashes and insert them back into the payload file.
  signed_payload_sig_file = common.MakeTempFile(prefix="signed-sig-",
                                                suffix=".bin")
  signed_metadata_sig_file = common.MakeTempFile(prefix="signed-sig-",
                                                 suffix=".bin")

  # 3a. 构造openssl命令使用rsa_key对payload哈希进行签名
  # openssl pkeyutl -sign -inkey /tmp/key-oQvVbH.key \
  #                       -pkeyopt digest:sha256 \
  #                       -in /tmp/sig-Cdhb80.bin \
  #                       -out /tmp/signed-sig-2UOQ1d.bin
  #
  # 3a. Sign the payload hash.
  if OPTIONS.payload_signer is not None:
    cmd = [OPTIONS.payload_signer]
    cmd.extend(OPTIONS.payload_signer_args)
  else:
    cmd = ["openssl", "pkeyutl", "-sign",
           "-inkey", rsa_key,
           "-pkeyopt", "digest:sha256"]
  cmd.extend(["-in", payload_sig_file,
              "-out", signed_payload_sig_file])

  p1 = common.Run(cmd, stdout=subprocess.PIPE)
  p1.wait()
  assert p1.returncode == 0, "openssl sign payload failed"

  # 3b. 构造openssl命令使用rsa_key对metadata哈希进行签名
  # openssl pkeyutl -sign -inkey /tmp/key-oQvVbH.key \
  #                       -pkeyopt digest:sha256 \
  #                       -in /tmp/sig-LDz25q.bin \
  #                       -out /tmp/signed-sig-08K2oF.bin
  # 
  # 3b. Sign the metadata hash.
  if OPTIONS.payload_signer is not None:
    cmd = [OPTIONS.payload_signer]
    cmd.extend(OPTIONS.payload_signer_args)
  else:
    cmd = ["openssl", "pkeyutl", "-sign",
           "-inkey", rsa_key,
           "-pkeyopt", "digest:sha256"]
  cmd.extend(["-in", metadata_sig_file,
              "-out", signed_metadata_sig_file])
  p1 = common.Run(cmd, stdout=subprocess.PIPE)
  p1.wait()
  assert p1.returncode == 0, "openssl sign metadata failed"

  # 3c. 构造使用脚本将payload签名和metadata签名写回payload数据的命令并执行
  # brillo_update_payload sign --unsigned_payload /tmp/payload-YqkYe1.bin \
  #                            --payload /tmp/signed-payload-102BNs.bin \
  #                            --signature_size 256 \
  #                            --metadata_signature_file /tmp/signed-sig-08K2oF.bin \
  #                            --payload_signature_file /tmp/signed-sig-2UOQ1d.bin
  #
  # 3c. Insert the signatures back into the payload file.
  signed_payload_file = common.MakeTempFile(prefix="signed-payload-",
                                            suffix=".bin")
  cmd = ["brillo_update_payload", "sign",
         "--unsigned_payload", payload_file,
         "--payload", signed_payload_file,
         "--signature_size", "256",
         "--metadata_signature_file", signed_metadata_sig_file,
         "--payload_signature_file", signed_payload_sig_file]
  p1 = common.Run(cmd, stdout=subprocess.PIPE)
  p1.wait()
  assert p1.returncode == 0, "brillo_update_payload sign failed"

  #
  # 4. 提取payload文件的properties数据
  #
  # 构造使用脚本提取payload properties的命令并执行
  # brillo_update_payload properties --payload /tmp/signed-payload-102BNs.bin \
  #                                  --properties_file /tmp/payload-properties-UoBiUx.txt
  # 
  # 4. Dump the signed payload properties.
  properties_file = common.MakeTempFile(prefix="payload-properties-",
                                        suffix=".txt")
  cmd = ["brillo_update_payload", "properties",
         "--payload", signed_payload_file,
         "--properties_file", properties_file]
  p1 = common.Run(cmd, stdout=subprocess.PIPE)
  p1.wait()
  assert p1.returncode == 0, "brillo_update_payload properties failed"

  #
  # 向properties文件添加其它属性
  #
  # 这里主要是根据OPTIONS.wipe_user_data选项决定是否往properties添加"POWERWASH=1"
  # OPTIONS.wipe_user_data选项从命令行参数"-w", "--wipe_user_data"解析得到，所以默认情况下为False
  #
  if OPTIONS.wipe_user_data:
    with open(properties_file, "a") as f:
      f.write("POWERWASH=1\n")
    metadata["ota-wipe"] = "yes"

  #
  # 将payload和properties以及metadata数据写入output文件中
  #    payload: payload.bin
  # properties: payload_properties.txt
  #   metadata: META-INF/com/android/metadata
  # 
  # Add the signed payload file and properties into the zip.
  common.ZipWrite(output_zip, properties_file, arcname="payload_properties.txt")
  common.ZipWrite(output_zip, signed_payload_file, arcname="payload.bin",
                  compress_type=zipfile.ZIP_STORED)

  #
  # 向META-INF/com/android/metadata写入metadata数据
  # 在我测试的平台上写入的数据如下：
  # $ cat META-INF/com/android/metadata 
  # ota-required-cache=0
  # ota-type=AB
  # post-build=broadcom/bcm72604usff/bcm72604usff:7.1.1/NMF27D/rg935706151800:userdebug/test-keys
  # post-build-incremental=eng.rg9357.20180615.180010
  # post-timestamp=1529056810
  # pre-build=broadcom/bcm72604usff/bcm72604usff:7.1.1/NMF27D/rg935706151800:userdebug/test-keys
  # pre-build-incremental=eng.rg9357.20180615.180010
  # pre-device=bcm72604usff
  #
  WriteMetadata(metadata, output_zip)

  #
  # 将dm-verity相关的care_map数据写入output文件中
  #
  # 我在制作的升级包里面看到的care_map.txt的内容为：
  # $ cat care_map.txt 
  # /dev/block/by-name/system
  #
  # If dm-verity is supported for the device, copy contents of care_map
  # into A/B OTA package.
  if OPTIONS.info_dict.get("verity") == "true":
    target_zip = zipfile.ZipFile(target_file, "r")
    care_map_path = "META/care_map.txt"
    namelist = target_zip.namelist()
    if care_map_path in namelist:
      care_map_data = target_zip.read(care_map_path)
      common.ZipWriteStr(output_zip, "care_map.txt", care_map_data)
    else:
      print "Warning: cannot find care map file in target_file package"
    common.ZipClose(target_zip)

  #
  # 使用OPTIONS.package_key对output文件进行签名
  #
  # 签名操作分为两步：
  # 1. 使用openssl命令检查package_key为unencrypted的private key
  # openssl pkcs8 -in build/target/product/security/testkey.pk8 -inform DER -nocrypt
  #
  # 2. 调用signapk.jar对output文件进行签名
  # java -Xmx2048m -Djava.library.path=out/host/linux-x86/lib64 \
  #                -jar out/host/linux-x86/framework/signapk.jar \
  #                -w build/target/product/security/testkey.x509.pem \
  #                build/target/product/security/testkey.pk8 /tmp/tmpNuS8M4 dist/update.zip
  #
  # Sign the whole package to comply with the Android OTA package format.
  common.ZipClose(output_zip)
  SignOutput(temp_zip_file.name, output_file)
  temp_zip_file.close()
```

`WriteABOTAPackageWithBrilloScript()`函数逻辑非常清晰，也包含了详细的注释，分析时没有太大难度。该函数包含了A/B系统制作升级包的所有步骤，归纳如下：
1. 准备制作升级包需要的key
   - 用于升级包签名的package_key
   - 用于payload数据和metadata数据签名的payload_signer
2. 准备升级包的metadata
   - 这里的metadata指升级包metadata文件中的数据，而非payload.bin中的metadata数据
3. 制作升级包
   - 生成payload文件
   - 提取payload数据和metadata数据的哈希值
   - 对payload哈希和metadata哈希数据使用payload_signer进行签名
   - 提取payload文件的properties数据并更新
   - 将payload文件, properties文件, metadata文件以及care_map文件写入升级包文件
4. 使用package_key对升级包文件进行签名

整个升级包制作的过程中主要使用了两支key，分别由`OPTIONS.package_key`和`payload_signer`指定。

顾名思义，前者`package_key`用于对整个升级包`update.zip`进行签名，后者`payload_signer`用于对升级数据`payload.bin`中的`payload`和`metadata`签名。
在制作升级包时，这两支key均可以通过命令行参数"`-k`"/"`--package_key`"或"`--payload_signer`"设置。

在没有设置的情况下，二者默认使用系统目录下的"build/target/product/security/testkey"文件作为key的来源。

### <span id="2.4">2.4 脚本`ota_from_target_files`总结</span>

脚本`ota_from_target_files`的内容大概有2100+行，其中大部分都是制作传统的非A/B系统升级包有关，制作A/B系统的升级包的逻辑非常简单。

执行升级包制作命令时，`main()`函数解析命令行参数，然后加载target包并提取相应文件(主要是`META/misc_info.txt`和`SYSTEM/build.prop`)信息用于创建键值对key/value集合。如果键值对集合中"ab_update"键的值为true，则判断当前为A/B系统制作升级包。随后，将整个升级包的制作都交给函数`WriteABOTAPackageWithBrilloScript()`处理。后者包含了A/B系统制作升级包的所有步骤：

1. 准备制作升级包需要的key
   - 包括对升级数据(payload和metadata)签名的`payload_signer`和升级包自身签名的`package_key`。
2. 准备升级包的metadata
   - 这里的metadata指升级包metadata文件中的数据，而非payload.bin中的metadata数据
3. 制作升级包
   - 3.1 生成payload文件
   - 3.2 提取payload数据和metadata数据的哈希值
   - 3.3 对payload哈希和metadata哈希数据使用payload_signer进行签名
   - 3.4 提取payload文件的properties数据并更新
   - 3.5 将payload文件, properties文件, metadata文件以及care_map文件写入升级包文件
4. 使用package_key对升级包文件进行签名

其中，将制作升级包的第3步中对payload数据的处理(3.1, 3.2, 3.4)打包成一些shell命令，交由`brillo_update_payload`脚本进行处理。

## <span id="3">3. 脚本`brillo_update_payload`</span>

脚本`brillo_update_payload`位于目录`system/update_engine/scripts`中，定义了很多可供调用的函数，除去这些函数，整个脚本的主要逻辑就显得比较简单，最重要的部分如下：
```
case "$COMMAND" in
  generate) validate_generate
            cmd_generate
            ;;
  hash) validate_hash
        cmd_hash
        ;;
  sign) validate_sign
        cmd_sign
        ;;
  properties) validate_properties
              cmd_properties
              ;;
esac
```
这段代码根据`$COMMAND`的不同取值，执行不同的操作。每个`$COMMAND`对应的操作都会调用两个函数，一个是`validate_xxx`，一个是`cmd_xxx`。前者主要用于验证命令行是否传递了所需要的参数，后者用于执行对应的操作，所以真正的重点在`cmd_xxx`函数。

在升级包的制作过程中，`WriteABOTAPackageWithBrilloScript()`函数前后共有4次调用`brillo_update_payload`，对应于上面的4种情况，按顺序分别如下:

> 为了见名知意，已经将调用命令中杂乱无章的临时文件名替换为有意义的文件名。

```
#
# 1. 生成payload文件
#    使用`brillo_update_payload`脚本生成payload数据：
brillo_update_payload generate --payload /tmp/payload_file.bin \
                               --target_image dist/new.zip \
                               --source_image dist/old.zip

#
# 2. 生成payload和metadata数据的哈希值
#    使用`brillo_update_payload`脚本从payload数据生成payload哈希和metadata哈希：
brillo_update_payload hash --unsigned_payload /tmp/payload_file.bin \
                           --signature_size 256 \
                           --metadata_hash_file /tmp/metadata_sig_file.bin \
                           --payload_hash_file /tmp/payload_sig_file.bin

#
# 3. 将payload签名和metadata签名写回payload文件
#    使用`brillo_update_payload`脚本将payload签名和metadata签名写回payload文件
brillo_update_payload sign --unsigned_payload /tmp/payload_file.bin \
                           --payload /tmp/signed_payload_file.bin \
                           --signature_size 256 \
                           --metadata_signature_file /tmp/signed_metadata_sig_file.bin \
                           --payload_signature_file /tmp/signed_payload_sig_file.bin

#
# 4. 提取payload文件的properties数据
#    构造使用脚本提取payload properties的命令并执行
brillo_update_payload properties --payload /tmp/signed_payload_file.bin \
                                 --properties_file /tmp/payload_properties_file.txt
```

下面对这4个调用的命令逐个分析。

### <span id="3.1">3.1 生成payload文件</span>

使用`brillo_update_payload`脚本生成payload数据：
```
brillo_update_payload generate --payload /tmp/payload_file.bin \
                               --target_image dist/new.zip \
                               --source_image dist/old.zip
```

对于`generate`操作，执行`case`语句中`$COMMAND`为`generate`的分支。

在该分支中，`validate_generate`函数用于验证命令行是否设置了`payload`和`target_image`参数，`cmd_generate`函数根据传入的参数执行payload.bin的`generate`工作。

#### <span id="cmd_generate">`cmd_generate()`函数</span>
```
cmd_generate() {
  #
  # 设置payload_type
  #
  # 根据是否传入source_image参数来确定当前是以delta还是full的方式生成payload
  #
  local payload_type="delta"
  if [[ -z "${FLAGS_source_image}" ]]; then
    payload_type="full"
  fi

  echo "Extracting images for ${payload_type} update."

  #
  # 从target/source的zip包中提取boot/system image
  # 提取到的文件路径存放在 DST_PARTITIONS/SRC_PARTITIONS数组中
  #
  # 关于具体的操作，请参考后随后的extract_image()函数注解
  extract_image "${FLAGS_target_image}" DST_PARTITIONS
  if [[ "${payload_type}" == "delta" ]]; then
    extract_image "${FLAGS_source_image}" SRC_PARTITIONS
  fi

  echo "Generating ${payload_type} update."
  
  # 构造指示payload文件的out_file参数，如：-out_file=dist/payload.bin
  # Common payload args:
  GENERATOR_ARGS=( -out_file="${FLAGS_payload}" )

  local part old_partitions="" new_partitions="" partition_names=""
  #
  # 循环操作DST_PARTITIONS[boot,system]分区
  # 获取分区名boot, system和对应的target, source包里提取到的image文件名
  # partition_names=boot:system
  # new_partitions=target包中提取的boot和system image的文件名，用':'分隔
  # old_partitions=source包中提取的boot和system image的文件名，用':'分隔
  #
  for part in "${!DST_PARTITIONS[@]}"; do
    # 检查partition_names是否为空
    if [[ -n "${partition_names}" ]]; then
      partition_names+=":"
      new_partitions+=":"
      old_partitions+=":"
    fi
    partition_names+="${part}"
    new_partitions+="${DST_PARTITIONS[${part}]}"
    old_partitions+="${SRC_PARTITIONS[${part}]:-}"
  done

  #
  # 构造包含partition_names和new_partitions的参数
  # 如：
  # -out_file=dist/payload.bin \
  # -partition_names=boot:system \
  # -new_partitions=/tmp/boot.img.oiHmvn:/tmp/system.raw.ZkArkk
  #
  # Target image args:
  GENERATOR_ARGS+=(
    -partition_names="${partition_names}"
    -new_partitions="${new_partitions}"
  )

  # 如果是delta的payload, 添加old_partitions参数和minor_version/zlib_fingerprint
  # 我测试的zip包中不包含zlib_fingerprint信息。所以这里构造的参数如下：
  # -out_file=dist/payload.bin \
  # -partition_names=boot:system \
  # -new_partitions=/tmp/boot.img.oiHmvn:/tmp/system.raw.ZkArkk \
  # -old_partitions=/tmp/boot.img.cXD4Dt:/tmp/system.raw.IlRpgW \
  # --minor_version=3
  #
  if [[ "${payload_type}" == "delta" ]]; then
    # Source image args:
    GENERATOR_ARGS+=(
      -old_partitions="${old_partitions}"
    )
    if [[ -n "${FORCE_MINOR_VERSION}" ]]; then
      GENERATOR_ARGS+=( --minor_version="${FORCE_MINOR_VERSION}" )
    fi
    if [[ -n "${ZLIB_FINGERPRINT}" ]]; then
      GENERATOR_ARGS+=( --zlib_fingerprint="${ZLIB_FINGERPRINT}" )
    fi
  fi

  # 添加major_version参数
  if [[ -n "${FORCE_MAJOR_VERSION}" ]]; then
    GENERATOR_ARGS+=( --major_version="${FORCE_MAJOR_VERSION}" )
  fi

  # 如果制作脚本有传入metadata_size_file参数，则添加metadata_size_file参数
  # 我测试时没有传入metadata_size_file参数
  if [[ -n "${FLAGS_metadata_size_file}" ]]; then
    GENERATOR_ARGS+=( --out_metadata_size_file="${FLAGS_metadata_size_file}" )
  fi

  # 如果有指定POSTINSTALL_CONFIG_FILE，则添加new_postinstall_config_file参数
  # 变量POSTINSTALL_CONFIG_FILE默认为空
  if [[ -n "${POSTINSTALL_CONFIG_FILE}" ]]; then
    GENERATOR_ARGS+=(
      --new_postinstall_config_file="${POSTINSTALL_CONFIG_FILE}"
    )
  fi

  #
  # 调用可执行文件delta_generator，传入上面构造的参数GENERATOR_ARGS，用于生成payload.bin
  # 所以我最后测试时，这里构造并执行的命令如下：
  # delta_generator -out_file=dist/payload.bin \
  #                 -partition_names=boot:system \
  #                 -new_partitions=/tmp/boot.img.oiHmvn:/tmp/system.raw.ZkArkk \
  #                 -old_partitions=/tmp/boot.img.cXD4Dt:/tmp/system.raw.IlRpgW \
  #                 --minor_version=3 --major_version=2
  #
  echo "Running delta_generator with args: ${GENERATOR_ARGS[@]}"
  "${GENERATOR}" "${GENERATOR_ARGS[@]}"

  echo "Done generating ${payload_type} update."
}
```

总结下`cmd_generate()`里面的操作：
1. 根据执行时是否传入了source_image参数，确定是生成全量(full)还是增量(delta)方式的payload.bin;
2. 调用`extract_image()`解压缩提取target/source的zip包中的"IMAGES/{boot,system}.img"文件到临时文件夹;
3. 根据解压缩的boot和system image的临时文件路径构造generator的参数;
4. 调用delta_generator，并传入前面构造的generator参数生成payload.bin;

所以`cmd_generator()`将payload.bin的生成再次交给了delta_generator程序：
```
delta_generator -out_file=dist/payload.bin \
             -partition_names=boot:system \
             -new_partitions=/tmp/boot.img.oiHmvn:/tmp/system.raw.ZkArkk \
             -old_partitions=/tmp/boot.img.cXD4Dt:/tmp/system.raw.IlRpgW \
             --minor_version=3 --major_version=2
```

> 关于`new_partitions`和`old_partitions`参数中的文件名：
> - `/tmp/boot.img.oiHmvn`和`/tmp/system.raw.ZkArkk`是从new.zip中提取的boot.img和system.img的临时文件名；
> - `/tmp/boot.img.cXD4Dt`和`/tmp/system.raw.IlRpgW`是从old.zip中提取的boot.img和system.img的临时文件名；
>
> 操作中，`/tmp`目录下的文件均为升级包制作过程中生成的临时文件，后续不再对命令中的临时文件名进行解释。

> 实际上这里称为转发是不准确的，因为在转发前，`brillo_update_payload`会先提取target和source对应zip包(即new.zip和old.zip)中的boot.img和system.img文件，并进行适当的处理。(所谓的处理就是，如果原来是sparse image, 则转换为raw image)

后面会对`delta_generator`的操作进行详细分析。

#### <span id="extract_image">`extract_image()`函数</span>
```
# extract_image <image> <partitions_array>
#
# Detect the format of the |image| file and extract its updatable partitions
# into new temporary files. Add the list of partition names and its files to the
# associative array passed in |partitions_array|.
extract_image() {
  local image="$1"

  #
  # 检查image文件的前4字节确定升级文件类型
  #
  
  #
  # 1. Brillo类型的文件是zip包，所以检查zip文件头部的magic header
  #
  # Brillo images are zip files. We detect the 4-byte magic header of the zip
  # file.
  local magic=$(head --bytes=4 "${image}" | hexdump -e '1/1 "%.2x"')
  if [[ "${magic}" == "504b0304" ]]; then
    echo "Detected .zip file, extracting Brillo image."
    #
    # 调用extract_image_brillo提取zip包文件
    #
    extract_image_brillo "$@"
    return
  fi

  #
  # 2. Chrome OS类型的文件是GPT分区, 所以检查头部的cgpt数据
  #
  # Chrome OS images are GPT partitioned disks. We should have the cgpt binary
  # bundled here and we will use it to extract the partitions, so the GPT
  # headers must be valid.
  if cgpt show -q -n "${image}" >/dev/null; then
    echo "Detected GPT image, extracting Chrome OS image."
    #
    # 调用extract_image_cros提取Chrome OS磁盘文件
    #
    extract_image_cros "$@"
    return
  fi

  die "Couldn't detect the image format of ${image}"
}
```

`extract_image()`根据传入文件的类型，判断当前待提取文件是Android系统(Brillo)使用的zip包还是Chrome OS系统的磁盘文件，然后调用不同的方法进行处理。对于Android A/B系统使用的zip包，`extract_image_brillo()`才是提取image文件的执行者。

#### <span id="extract_image_brillo">`extract_image_brillo()`函数</span>
```
# extract_image_brillo <target_files.zip> <partitions_array>
#
# Extract the A/B updated partitions from a Brillo target_files zip file into
# new temporary files.
extract_image_brillo() {
  # 获取传入参数
  local image="$1"
  local partitions_array="$2"

  #
  # 解压缩zip内的META/ab_partitions.txt文件，并提取分区信息
  #
  # android-7.1.1_r23$ cat dist/new/META/ab_partitions.txt 
  # boot
  # system
  #
  local partitions=( "boot" "system" )
  local ab_partitions_list
  # 生成临时文件"ab_partitions_list.XXXXXX"
  ab_partitions_list=$(create_tempfile "ab_partitions_list.XXXXXX")
  CLEANUP_FILES+=("${ab_partitions_list}")
  # 解压缩zip包的"META/ab_partitions.txt"到临时文件
  if unzip -p "${image}" "META/ab_partitions.txt" >"${ab_partitions_list}"; then
    # 检查文件中是否有包含特殊字符串，分区名不应该包含这样的字符串
    if grep -v -E '^[a-zA-Z0-9_-]*$' "${ab_partitions_list}" >&2; then
      die "Invalid partition names found in the partition list."
    fi
    # 提取文件内容作为操作的分区
    partitions=($(cat "${ab_partitions_list}"))
    # 检查分区数
    if [[ ${#partitions[@]} -eq 0 ]]; then
      die "The list of partitions is empty. Can't generate a payload."
    fi
  else
    warn "No ab_partitions.txt found. Using default."
  fi
  echo "List of A/B partitions: ${partitions[@]}"

  # All Brillo updaters support major version 2.
  FORCE_MAJOR_VERSION="2"

  #
  # 根据当前处理的zip文件是target包还是source包做不同的处理
  #
  # 如果当前zip是source包
  if [[ "${partitions_array}" == "SRC_PARTITIONS" ]]; then
    # Source image
    local ue_config=$(create_tempfile "ue_config.XXXXXX")
    CLEANUP_FILES+=("${ue_config}")
    # 提取META/update_engine_config.txt信息到临时文件ue_config.XXXXXX中
    if ! unzip -p "${image}" "META/update_engine_config.txt" \
        >"${ue_config}"; then
      warn "No update_engine_config.txt found. Assuming pre-release image, \
using payload minor version 2"
    fi
    #
    # 读取文件内PAYLOAD_MINOR_VERSION和PAYLOAD_MAJOR_VERSION的内容
    # 测试使用的文件内容如下：
    # android-7.1.1_r23$ cat dist/new/META/update_engine_config.txt 
    # PAYLOAD_MAJOR_VERSION=2
    # PAYLOAD_MINOR_VERSION=3
    #
    # For delta payloads, we use the major and minor version supported by the
    # old updater.
    FORCE_MINOR_VERSION=$(read_option_uint "${ue_config}" \
      "PAYLOAD_MINOR_VERSION" 2)
    FORCE_MAJOR_VERSION=$(read_option_uint "${ue_config}" \
      "PAYLOAD_MAJOR_VERSION" 2)

    # 检查PAYLOAD_MINOR_VERSION，
    # 如果<2，退出，因为Brillo要求delta升级方式至少为3
    # Brillo support for deltas started with minor version 3.
    if [[ "${FORCE_MINOR_VERSION}" -le 2 ]]; then
      warn "No delta support from minor version ${FORCE_MINOR_VERSION}. \
Disabling deltas for this source version."
      exit ${EX_UNSUPPORTED_DELTA}
    fi

    # 检查PAYLOAD_MINOR_VERSION，
    # 如果>4，则解压缩"META/zlib_fingerprint.txt"到ZLIB_FINGERPRINT
    if [[ "${FORCE_MINOR_VERSION}" -ge 4 ]]; then
      ZLIB_FINGERPRINT=$(unzip -p "${image}" "META/zlib_fingerprint.txt")
    fi
  else # 当前zip是target包的情况
    # Target image
    local postinstall_config=$(create_tempfile "postinstall_config.XXXXXX")
    CLEANUP_FILES+=("${postinstall_config}")
    # 解压缩"META/postinstall_config.txt"到POSTINSTALL_CONFIG_FILE
    if unzip -p "${image}" "META/postinstall_config.txt" \
        >"${postinstall_config}"; then
      POSTINSTALL_CONFIG_FILE="${postinstall_config}"
    fi
  fi

  local part part_file temp_raw filesize
  
  #
  # 对从"META/ab_partitions.txt"提取到的partition逐个操作
  #
  for part in "${partitions[@]}"; do
    part_file=$(create_tempfile "${part}.img.XXXXXX")
    CLEANUP_FILES+=("${part_file}")
    # 将"IMAGES/{boot,system}.img"释放到{boot,system}.img.xxxx临时文件
    unzip -p "${image}" "IMAGES/${part}.img" >"${part_file}"

    #
    # 检查{boot,system}.img文件头部的4个字节
    # 如果是"3aff26ed", 说明是sparse image，将其转换回raw image
    #
    # If the partition is stored as an Android sparse image file, we need to
    # convert them to a raw image for the update.
    local magic=$(head --bytes=4 "${part_file}" | hexdump -e '1/1 "%.2x"')
    if [[ "${magic}" == "3aff26ed" ]]; then
      temp_raw=$(create_tempfile "${part}.raw.XXXXXX")
      CLEANUP_FILES+=("${temp_raw}")
      echo "Converting Android sparse image ${part}.img to RAW."
      simg2img "${part_file}" "${temp_raw}"
      # At this point, we can drop the contents of the old part_file file, but
      # we can't delete the file because it will be deleted in cleanup.
      true >"${part_file}"
      part_file="${temp_raw}"
    fi

    # delta_generator only supports images multiple of 4 KiB. For target images
    # we pad the data with zeros if needed, but for source images we truncate
    # down the data since the last block of the old image could be padded on
    # disk with unknown data.
    #
    # 获取{boot,system}.img的文件大小
    # 对于source分区，则将其filesize向下截取到4K边界
    # 对于target分区，则将其filesize向上填充到4K边界
    #
    filesize=$(stat -c%s "${part_file}")
    if [[ $(( filesize % 4096 )) -ne 0 ]]; then
      if [[ "${partitions_array}" == "SRC_PARTITIONS" ]]; then
        echo "Rounding DOWN partition ${part}.img to a multiple of 4 KiB."
        : $(( filesize = filesize & -4096 ))
      else
        echo "Rounding UP partition ${part}.img to a multiple of 4 KiB."
        : $(( filesize = (filesize + 4095) & -4096 ))
      fi
      truncate_file "${part_file}" "${filesize}"
    fi

    #
    # 更新传入参数 partitions_array
    # 调用时:
    #        传入 DST_PARTITIONS/SRC_PARTITIONS，用于区分是source还是target;
    # 调用完:
    #        传出 DST_PARTITIONS[boot/system]或SRC_PARTITIONS[boot/system]
    #        用于指示提取的boot.img/system.img的路径
    eval "${partitions_array}[\"${part}\"]=\"${part_file}\""
    echo "Extracted ${partitions_array}[${part}]: ${filesize} bytes"
  done
}
```

`extract_image_brillo()`函数看起来复制，但其所做的操作却比较简单：
1. 从zip包的"META/ab_partitions.txt"文件中提取分区信息；
2. 从zip包中解压缩boot/system image文件到临时文件，如果文件是sparse image，则将其转换回raw image;
3. 以数组方式返回target/source的zip包提取到的boot/system raw image名字；

一句话，`extract_image_brillo()`函数提取zip包中的boot/system image文件用于后续处理。

#### <span id="payload_sumary">生成payload文件总结</span>

`brillo_update_payload`脚本中，通过函数`cmd_generate()`生成payload.bin。

操作上，`cmd_generate()`调用`extract_image()`提取zip包中IMAGES目录中的boot.img和system.img，如果提取得到的是sparse image格式文件，则还需要进一步使用simg2img工具将其转换为raw image格式。
如果指定了target和source制作增量包，则相应会提取到4个image文件(target和source包各自的boot.img/system.img)；如果只指定target制作全量包，则得到2个image文件(boot.img/system.img)。
然后，用提取到的boot.img和system.img的路径构造参数并传递给delta_generator应用程序。

以增量包为例，`cmd_generate()`调用delta_generator生成payload.bin的命令为：
```
delta_generator -out_file=dist/payload.bin \
                -partition_names=boot:system \
                -new_partitions=/tmp/boot.img.oiHmvn:/tmp/system.raw.ZkArkk \
                -old_partitions=/tmp/boot.img.cXD4Dt:/tmp/system.raw.IlRpgW \
                --minor_version=3 --major_version=2
```
所以，最终通过delta_generator去生成payload.bin文件。

### <span id="3.2">3.2 生成payload数据和metadata数据的哈希值</span>

使用`brillo_update_payload`脚本从payload数据生成payload哈希和metadata哈希：
```
brillo_update_payload hash --unsigned_payload /tmp/payload_file.bin \
                           --signature_size 256 \
                           --metadata_hash_file /tmp/metadata_sig_file.bin \
                           --payload_hash_file /tmp/payload_sig_file.bin
```

对于`hash`操作，执行`case`语句中`$COMMAND`为`hash`的分支。

在该分支中，`validate_hash()`函数用于验证命令行是否设置了`signature_size`/`unsigned_payload`/`payload_hash_file`/`metadata_hash_file`等参数，然后`cmd_hash()`函数将这些参数传递给`delta_generator`去生成payload和metadata的哈希。

代码非常简单，甚至不需要注释：
```
cmd_hash() {
  "${GENERATOR}" \
      -in_file="${FLAGS_unsigned_payload}" \
      -signature_size="${FLAGS_signature_size}" \
      -out_hash_file="${FLAGS_payload_hash_file}" \
      -out_metadata_hash_file="${FLAGS_metadata_hash_file}"

  echo "Done generating hash."
}
```

以增量包为例，`cmd_hash()`调用delta_generator生成payload和metadata的哈希命令为：
```
delta_generator -in_file=/tmp/payload_file.bin \
                -signature_size=256 \
                -out_hash_file=/tmp/payload_sig_file.bin \
                -out_metadata_hash_file=/tmp/metadata_sig_file.bin
```
好吧，最终还是通过delta_generator去生成payload和metadata的哈希。

### <span id="3.3">3.3 将payload签名和metadata签名写回payload文件</span>

使用`brillo_update_payload`脚本将payload签名和metadata签名写回payload文件
```
brillo_update_payload sign --unsigned_payload /tmp/payload_file.bin \
                           --payload /tmp/signed_payload_file.bin \
                           --signature_size 256 \
                           --metadata_signature_file /tmp/signed_metadata_sig_file.bin \
                           --payload_signature_file /tmp/signed_payload_sig_file.bin
```

对于`sign`操作，执行`case`语句中`$COMMAND`为`sign`的分支。

在该分支中，`validate_sign()`函数用于验证命令行是否设置了`signature_size`/`unsigned_payload`/`payload`/`payload_signature_file`/`metadata_signature_file`等参数，然后`cmd_sign()`函数将这些参数传递给`delta_generator`去生成包含签名的payload.bin文件。

这里的代码也非常简单，不需要注释：
```
cmd_sign() {
  GENERATOR_ARGS=(
    -in_file="${FLAGS_unsigned_payload}"
    -signature_size="${FLAGS_signature_size}"
    -signature_file="${FLAGS_payload_signature_file}"
    -metadata_signature_file="${FLAGS_metadata_signature_file}"
    -out_file="${FLAGS_payload}"
  )

  if [[ -n "${FLAGS_metadata_size_file}" ]]; then
    GENERATOR_ARGS+=( --out_metadata_size_file="${FLAGS_metadata_size_file}" )
  fi

  "${GENERATOR}" "${GENERATOR_ARGS[@]}"
  echo "Done signing payload."
}
```

以增量包为例，`cmd_sign()`调用delta_generator将payload签名和metadata签名写回payload文件的命令为：
```
delta_generator -in_file=/tmp/payload_file.bin \
                -signature_size=256 \
                -signature_file=/tmp/signed_payload_file.bin \
                -metadata_signature_file=/tmp/signed_metadata_sig_file.bin \
                -out_file=/tmp/signed_payload_file.bin
```
> 虽然这里叫写回，其实并不是在原来的payload.bin文件上操作，而是使用`payload.bin`, `signed_payload_file.bin`和`signed_metadata_sig_file.bin`生成了一个新的`signed_payload_file.bin`文件。

好吧，最终也还是通过delta_generator去合并上payload哈希和metadata哈希。

### <span id="3.4">3.4 提取payload文件的properties数据</span>

构造使用脚本提取payload properties的命令并执行
```
brillo_update_payload properties --payload /tmp/signed_payload_file.bin \
                                 --properties_file /tmp/payload_properties_file.txt
```

对于`properties`操作，执行`case`语句中`$COMMAND`为`properties`的分支。

在该分支中，`validate_properties()`函数用于验证命令行是否设置了`payload`/`properties_file`等参数，然后`cmd_properties()`函数将这些参数传递给`delta_generator`去提取payload文件的properties数据。

代码如下：
```
cmd_properties() {
  "${GENERATOR}" \
      -in_file="${FLAGS_payload}" \
      -properties_file="${FLAGS_properties_file}"
}
```

以增量包为例，`cmd_properties()`调用delta_generator提取payload文件的properties数据的命令为：
```
delta_generator -in_file=/tmp/signed_payload_file.bin \
                -properties_file=/tmp/payload_properties_file.txt
```

所以，delta_generator也负责提取payload文件的properties数据的操作。

### <span id="3.5">3.5 脚本brillo_update_payload总结</span>

在生成payload.bin时，需要4步操作：
1. 生成payload文件
2. 生成payload和metadata数据的哈希值
3. 将payload签名和metadata签名写回payload文件
4. 提取payload文件的properties数据

而`brillo_update_payload`脚本将这4步操作中的命令转发给`delta_generator`。分别如下：

- 生成payload文件

```
delta_generator -out_file=dist/payload.bin \
                -partition_names=boot:system \
                -new_partitions=/tmp/boot.img.oiHmvn:/tmp/system.raw.ZkArkk \
                -old_partitions=/tmp/boot.img.cXD4Dt:/tmp/system.raw.IlRpgW \
                --minor_version=3 --major_version=2
```

- 生成payload和metadata数据的哈希值

```
delta_generator -in_file=/tmp/payload_file.bin \
                -signature_size=256 \
                -out_hash_file=/tmp/payload_sig_file.bin \
                -out_metadata_hash_file=/tmp/metadata_sig_file.bin
```

- 将payload签名和metadata签名写回payload文件

```
delta_generator -in_file=/tmp/payload_file.bin \
                -signature_size=256 \
                -signature_file=/tmp/signed_payload_file.bin \
                -metadata_signature_file=/tmp/signed_metadata_sig_file.bin \
                -out_file=/tmp/signed_payload_file.bin
```

- 提取payload文件的properties数据

```
delta_generator -in_file=/tmp/signed_payload_file.bin \
                -properties_file=/tmp/payload_properties_file.txt
```

然后余下的操作都在`delta_generator`里面了，下一篇将会对`delta_generator`代码中的这4个操作进行详细分析。

## 4. 联系和福利

- 个人微信公众号“洛奇看世界”，一个大龄码农的救赎之路。
  - 公众号回复关键词“Android电子书”，获取超过150本Android相关的电子书和文档。电子书包含了Android开发相关的方方面面，从此你再也不需要到处找Android开发的电子书了。
  - 公众号回复关键词“个人微信”，获取个人微信联系方式。<font color="red">我组建了一个Android OTA的讨论组，联系我，说明Android OTA，拉你进组一起讨论。</font>

  ![image](https://img-blog.csdn.net/20180507223120679)