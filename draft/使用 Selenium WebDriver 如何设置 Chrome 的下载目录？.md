使用 Selenium WebDriver 如何设置 Chrome 的下载目录？



> 关于 Chrome 的一些选项设置，建议参考: https://chromedriver.chromium.org/capabilities

#### 设置下载目录

以下代码可用于配置 Chrome 以将文件下载到特定目录。但是，有几个注意事项需要注意：

- Chrome 不允许使用某些目录进行下载。特别是，您不能将桌面文件夹用作下载目录。在 Linux 上，您也不能使用主目录进行下载。由于禁止目录的确切列表可能会发生变化，因此建议您使用对系统没有特殊意义的目录。
- ChromeDriver 不会自动等待下载完成。如果您调用 driver.quit() 的时间过早，Chrome 可能会在下载完成之前终止。
- 相对路径并不总是有效。为获得最佳结果，请改用完整路径。
- 在 Windows 上，使用“\”作为路径分隔符。在 Windows 上使用“/”不可靠。

```
ChromeOptions options = new ChromeOptions ( ) ; 
Map <String, Object> prefs = new HashMap <String, Object> ( ) ; 
首选项。put ( " download.default_directory " , " /directory/ path " ) ; 
选项。setExperimentalOption （“首选项” ，首选项）;   
```