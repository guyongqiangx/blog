# 20230201-[已解决]Ubuntu Server 使用 jenkins 运行 selenium webdriver 失败

我在多台 ubuntu server 上使用 jenkins 账户运行 selenium webdriver 时都遇到了这个问题。

包括 ubuntu 16.04, ubuntu 18.04 和 ubuntu 20.04 的 server 系统，这是一个普遍存在的问题。



失败时的错误信息如下：

```bash
selenium.common.exceptions.WebDriverException: Message: unknown error: Chrome failed to start: crashed.
  (unknown error: DevToolsActivePort file doesn't exist)
  (The process started from chrome location /usr/bin/google-chrome is no longer running, so ChromeDriver is assuming that Chrome has crashed.)
```



下面是我尝试使用一个简单脚本复现问题时的详细日志：

```bash
(venv) jenkins@guyongqiangx:/scratch/test/sampleKeywordTest$ python3 Others/testSample.py 
Traceback (most recent call last):
  File "Others/testSample.py", line 28, in <module>
    driver = webdriver.Chrome(service=service, options=chrome_options)
  File "/scratch/test/venv/lib/python3.8/site-packages/selenium/webdriver/chrome/webdriver.py", line 69, in __init__
    super().__init__(DesiredCapabilities.CHROME['browserName'], "goog",
  File "/scratch/test/venv/lib/python3.8/site-packages/selenium/webdriver/chromium/webdriver.py", line 92, in __init__
    super().__init__(
  File "/scratch/test/venv/lib/python3.8/site-packages/selenium/webdriver/remote/webdriver.py", line 277, in __init__
    self.start_session(capabilities, browser_profile)
  File "/scratch/test/venv/lib/python3.8/site-packages/selenium/webdriver/remote/webdriver.py", line 370, in start_session
    response = self.execute(Command.NEW_SESSION, parameters)
  File "/scratch/test/venv/lib/python3.8/site-packages/selenium/webdriver/remote/webdriver.py", line 435, in execute
    self.error_handler.check_response(response)
  File "/scratch/test/venv/lib/python3.8/site-packages/selenium/webdriver/remote/errorhandler.py", line 247, in check_response
    raise exception_class(message, screen, stacktrace)
selenium.common.exceptions.WebDriverException: Message: unknown error: Chrome failed to start: crashed.
  (unknown error: DevToolsActivePort file doesn't exist)
  (The process started from chrome location /usr/bin/google-chrome is no longer running, so ChromeDriver is assuming that Chrome has crashed.)
Stacktrace:
#0 0x5565e64e1463 <unknown>
#1 0x5565e62a58d8 <unknown>
#2 0x5565e62cdb6a <unknown>
#3 0x5565e62c8c05 <unknown>
#4 0x5565e630c802 <unknown>
#5 0x5565e630c2af <unknown>
#6 0x5565e6304443 <unknown>
#7 0x5565e62d53c5 <unknown>
#8 0x5565e62d6531 <unknown>
#9 0x5565e6533dce <unknown>
#10 0x5565e6537192 <unknown>
#11 0x5565e651893e <unknown>
#12 0x5565e6538103 <unknown>
#13 0x5565e650bd85 <unknown>
#14 0x5565e65590a8 <unknown>
#15 0x5565e6559239 <unknown>
#16 0x5565e6574492 <unknown>
#17 0x7f78ae631609 start_thread

(venv) jenkins@guyongqiangx:/scratch/test/sampleKeywordTest$ 
```



但是如果我使用另一个账户进行测试则表现正常：

```bash
(venv) rocky@guyongqiangx:/scratch/test/sampleKeywordTest$ python3 Others/testSample.py 
URL: http://bp3.newbiestart.net/, Title: Home - BP3
Checkbox is not selected, click it
Checkbox is selected
URL: http://bp3.newbiestart.net/, Title: Home - BP3
(venv) rocky@guyongqiangx:/scratch/test/sampleKeywordTest$ 
```



这两个测试的唯一区别是账户不同，一个是普通账户 rocky，另外一个是 jenkins 账户。

这个问题持续了好久，能想到的各种环境因素都试过了，也根据前面的错误信息使用百度和谷歌翻了很多网页，一直没有解决。



直到有一天，我突然想起来，应该缩小排查的范围，使用 jenkins 直接运行 Chrome 无头浏览器(headless) 看看。

果不其然，在 jenkins 上运行 Chrome 无头浏览器也失败了，惊喜的是，这次运行给出了明确的错误信息。

以下是我分别使用普通账户和 jenkins 账户在命令函运行 Chrome 无头浏览器的日志:

- 使用 rocky 账户运行 google-chrome headless 正常

```
(venv) rocky@guyongqiangx:/scratch/test/sampleKeywordTest$ google-chrome --headless --disable-gpu --dump-dom https://www.baidu.com
[1220/215744.646207:WARNING:bluez_dbus_manager.cc(247)] Floss manager not present, cannot set Floss enable/disable.
[1220/215744.672649:WARNING:sandbox_linux.cc(380)] InitializeSandbox() called with multiple threads in process gpu-process.
<!DOCTYPE html>
<html><head>
...
... 这中间是正常的网页内容
...
</script><script defer="" src="//hectorstatic.baidu.com/96c9c06653ba892e.js"></script></body></html>
(venv) rocky@guyongqiangx:/scratch/test/sampleKeywordTest$ 
```

- 使用 jenkins 账户运行 google-chrome headless 异常

```
(venv) jenkins@guyongqiangx:/scratch/test/sampleKeywordTest$ google-chrome --headless --disable-gpu --dump-dom https://www.baidu.com
[1220/215611.305649:ERROR:filesystem_posix.cc(63)] mkdir /tmp/Crashpad/new: Permission denied (13)
[1220/215611.306044:ERROR:socket.cc(120)] recvmsg: Connection reset by peer (104)
Trace/breakpoint trap (core dumped)
(venv) jenkins@guyongqiangx:/scratch/test/sampleKeywordTest$ 
```

这里提示无法创建 `/tmp/Crashpad/new` 目录，原因是 "Permission denied".



转到 `/tmp` 目录下一看，"Crashpad" 目录的主人是 rocky 账户，而且 jenkins 没有任何权限。

```
(venv) rocky@guyongqiangx:/scratch/test/sampleKeywordTest$ ls -lh /tmp/
total 3.0M
drwxrwxr-x 3 andrew users   4.0K Oct 31 17:52 8863542
drwxrwxr-x 3 andrew users   4.0K Oct 31 18:04 8882707
-rw-r----- 1 andrew users    49K Dec  6 17:13 adb.36670.log
drwx------ 6 rocky  users   4.0K Dec 20 20:53 Crashpad
```



对比虚拟机上可以正常执行 jenkins 的环境：

```
(venv) ygu@bp3tester:/local/bp3Test/sampleKeywordTest$ ls -lh /tmp/
total 3.3M
drwx------ 6 jenkins jenkins 4.0K Dec  3 00:06 Crashpad
drwxr-xr-x 2 jenkins jenkins 4.0K Dec 20 21:45 hsperfdata_jenkins
```

这里可以看到，虚拟机上正常执行环境的 `/tmp/Crashpad` 属于 jenkins 账户。



找到了原因，解决的办法就容易了。

有以下几种办法：

1. 将 `/tmp/Crashpad` 目录的拥有者更改为 jenkins

   ```bash
   $ sudo chown -R jenkins:jenkins /tmp/Crashpad 
   ```


2. 不改变 `/tmp/Crashpad` 目录的拥有者，但将其权限设置为 777，让 jenkins 账户也可以操作

   ```bash
   $ sudo chmod -R 777 /tmp/Crashpad
   ```



问题完美解决。



如果你在 ubuntu server 上运行 selenium webdriver 失败，建议做如下检查：

1. server 上是否安装了 Chrome 浏览器应用?

2. 运行 selenium webdriver 时是否下载并指定了 Chrome 对应的 webdriver?

3. 使用 jenkins 在没有图形界面的环境下运行 selenium，需要将其设置为无头模式(headless)

   ```python
   from selenium.webdriver.chrome.service import Service as ChromeService
   from selenium.webdriver.chrome.options import Options as ChromeOptions
   from webdriver_manager.chrome import ChromeDriverManager
   
   chrome_options = ChromeOptions()
   
   chrome_options.add_argument('--no-sandbox')
   chrome_options.add_argument('--headless')
   chrome_options.add_argument('--disable-extensions')
   chrome_options.add_argument('--disable-gpu')
   chrome_options.add_argument('--disable-dev-shm-usage')
   
   # 这里使用 ChromeDriverManager 自动安装 webdriver
   chrome_service = ChromeService(executable_path=ChromeDriverManager().install())
   driver = webdriver.Chrome(service=chrome_service, options=chrome_options)
   ...
   ```


4. 尝试在命令行直接以无头模式运行 Chrome

   ```bash
   $ google-chrome --headless --disable-gpu --dump-dom https://www.baidu.com
   ```

   