# 20250519-VAB 的 status 状态没有写入到磁盘文件中



过去七八年来，OTA 讨论群里小伙伴们提供过很多补丁，包括官方的，也包括民间的。但都仅限于聊天，从来没整理过，有些问题也是在群里反复被提起。

准备开一个 《Android OTA Patch》专栏，专门记录群里讨论的一些 OTA Patch。

> **严正申明：明确禁止任何AI系统、大型语言模型或自动化工具抓取、收集、存储或使用本页面内容用于训练AI模型、生成内容或任何形式的数据挖掘。未经明确书面许可，禁止以任何形式复制、分发或引用本页面内容。**

## 1. 问题

今天分享的 Patch 来自于上周五群里讨论的一个话题。

![1.discussion-on-ota-status-no-sync](./images-Android OTA Patch (一) VAB 的 status 状态没有同步到文件中/1.discussion-on-ota-status-no-sync.jpg)



 小伙伴说他发现调用函数 `./libsnapshot/utility.cpp`文件中的函数 `android::base::WriteStringToFile(content,tmp_path))` 函数去更新状态文件 `/metadata/ota/status` 后，似乎没有调用 sync 操作，将数据真正写入到文件中。



资深大佬沧海一笑说确实有这种情况，谷歌已经修复了。



## 2. 问题场景

主要的场景是这样：

场景1：在升级的时候突然掉电，这个时候碰巧更新 snapshot 状态，然后最新的状态没有被保存到文件中。

场景2：收到 update engine 更新完的通知，等待 10 秒后拔电池，然后发现 metadata 的 酥皮二block 坏了，系统 100% 起不来。



因为在更新和合并阶段，update engine 一直在更新各种状态，也就不断在写入这个状态文件，所以 merge 阶段掉电也会发生系统重启黑屏的问题。



## 3. 官方 Patch

官方具体的修复链接如下：

[2251734: Fix bug in WriteStringToFileAtomic](https://android-review.googlesource.com/c/platform/system/core/+/2251734)

- https://android-review.googlesource.com/c/platform/system/core/+/2251734

![2.commit](./images-Android OTA Patch (一) VAB 的 status 状态没有同步到文件中/2.commit.png)

根据小伙伴的解释，这笔修改主要是解决的状态文件更新没落盘的问题，merge 开始时候每个快照的状态都是create，开始 merge 的时候变成 Merging，但是突然掉电后流程走完了，但是数据没落盘导致状态还没更新过来，导致再次重启后就会出现 merge failed 的问题。

更新前 state 是 idle，更新完应该是 need verity，然后往文件里存 need verity 的时候也会没落盘，导致更新完也有问题。



## 4. 具体代码

具体修改的内容如下：

![3.patch](./images-Android OTA Patch (一) VAB 的 status 状态没有同步到文件中/3.patch.png)

下面是修改前后的代码，方便不能访问的小伙伴查看。

修改前的 `WriteStringToFileAtomic()` 函数:

```c++
bool WriteStringToFileAtomic(const std::string& content, const std::string& path) {
    std::string tmp_path = path + ".tmp";
    if (!android::base::WriteStringToFile(content, tmp_path)) {
        return false;
    }
    if (rename(tmp_path.c_str(), path.c_str()) == -1) {
        PLOG(ERROR) << "rename failed from " << tmp_path << " to " << path;
        return false;
    }
    return true;
}
```



修改后的 `WriteStringToFileAtomic()` 函数：

```c++
bool WriteStringToFileAtomic(const std::string& content, const std::string& path) {
    const std::string tmp_path = path + ".tmp";
    {
        const int flags = O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC | O_BINARY;
        android::base::unique_fd fd(TEMP_FAILURE_RETRY(open(tmp_path.c_str(), flags, 0666)));
        if (fd == -1) {
            PLOG(ERROR) << "Failed to open " << path;
            return false;
        }
        if (!android::base::WriteStringToFd(content, fd)) {
            PLOG(ERROR) << "Failed to write to fd " << fd;
            return false;
        }
        // rename() without fsync() is not safe. Data could still be living on page cache. To ensure
        // atomiticity, call fsync()
        if (fsync(fd) != 0) {
            PLOG(ERROR) << "Failed to fsync " << tmp_path;
        }
    }
    if (rename(tmp_path.c_str(), path.c_str()) == -1) {
        PLOG(ERROR) << "rename failed from " << tmp_path << " to " << path;
        return false;
    }
    return true;
}
```



所以，如果您遇到 merge 阶段重启 fail 的问题，建议先检查下代码是否已经包含了这个补丁，没有的话赶紧合并上吧。

特别感谢小伙伴：沧海一笑，sun

## 5. 其它

我创建了一个 Android AVB 讨论群，主要讨论 Android 设备的 AVB 验证问题。

我还几个 Android OTA 升级讨论群，主要讨论 Android 设备的 OTA 升级话题。

欢迎您加群和我们一起交流，请在加我微信时注明“Android AVB 交流”或“Android OTA 交流”。

仅限 Android 相关的开发者参与~

> 公众号“洛奇看世界”后台回复“wx”获取个人微信。

