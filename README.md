# CrashExceptionHandler

[iOS Crash收集框架](http://www.cocoachina.com/articles/12301)

### iOS 崩溃千奇百怪，如何全面监控？

### 重点内容梳理

1、常见的导致崩溃的原因有哪些？

* 数组越界：索引越界，还有给数组添加了nil会崩溃
* 多线程问题：在子线程中进行 UI 更新可能会发生崩溃。多个线程进行数据的读取操作，因为处理时机不一致，比如有一个线程在置空数据的同时另一个线程在读取这个数据，可能会出现崩溃情况。
* 主线程无响应：如果主线程超过系统规定的时间无响应，就会被 Watchdog 杀掉，崩溃问题对应的异常编码是 0x8badf00d。
* 野指针：指针指向一个已删除的对象访问内存区域时，会出现野指针崩溃。

2.常见的崩溃分类
![](media/15747337113659/15827683801509.jpg)
通过这张图片，我们可以看到， KVO 问题、NSNotification 线程问题、数组越界、野指针等崩溃信息，是可以通过信号捕获的。但是，像后台任务超时、内存被打爆、主线程卡顿超阈值等信息，是无法通过信号捕捉到的。

### 信号可捕获的崩溃日志收集
收集崩溃日志最简单的方法，就是打开 Xcode 的菜单选择 Product -> Archive。
然后，在提交时选上“Upload your app’s symbols to receive symbolicated reports from Apple”，以后你就可以直接在 Xcode 的 Archive 里看到符号化后的崩溃日志了。
![](media/15747337113659/15827686994937.jpg)
这种时效性比较差。

目前很多公司的崩溃日志监控系统，都是通过[PLCrashReporter](https://github.com/microsoft/plcrashreporter)第三方开源库，然后上传到自己服务器上进行整体监控的。
`EXC_BAD_ACCESS` 这个异常会通过 SIGSEGV 信号发现有问题的线程。虽然信号的种类有很多，但是都可以通过注册 signalHandler 来捕获到。其实现代码，如下所示：

```
void registerSignalHandler(void) {
    signal(SIGSEGV, handleSignalException);
    signal(SIGFPE, handleSignalException);
    signal(SIGBUS, handleSignalException);
    signal(SIGPIPE, handleSignalException);
    signal(SIGHUP, handleSignalException);
    signal(SIGINT, handleSignalException);
    signal(SIGQUIT, handleSignalException);
    signal(SIGABRT, handleSignalException);
    signal(SIGILL, handleSignalException);
}

void handleSignalException(int signal) {
    NSMutableString *crashString = [[NSMutableString alloc]init];
    void* callstack[128];
    int i, frames = backtrace(callstack, 128);
    char** traceChar = backtrace_symbols(callstack, frames);
    for (i = 0; i <frames; ++i) {
        [crashString appendFormat:@"%s\n", traceChar[i]];
    }
    NSLog(crashString);
}
```

上面这段代码对各种信号都进行了注册，捕获到异常信号后，在处理方法 handleSignalException 里通过 backtrace_symbols 方法就能获取到当前的堆栈信息。堆栈信息可以先保存在本地，下次启动时再上传到崩溃监控服务器就可以了

#### 常见crash信号解释
SIGTERM

* 程序结束(terminate)信号，与SIGKILL不同的是该信号可以被阻塞和处理。通常用来要求程序自己正常退出。
* iOS中一般不会处理到这个信号

SIGSEGV

* invalid memory access (segmentation fault)
* 无效的内存地址引用信号(常见的野指针访问)
* 非ARC模式下，iOS中经常会出现在 Delegate对象野指针访问
* ARC模式下，iOS经常会出现在Block代码块内 强持有可能释放的对象

SIGINT

* external interrupt, usually initiated by the user
* 通常由用户输入的整型中断信号
* 在iOS中一般不会处理到该信号

SIGILL

* invalid program image, such as invalid instruction
* 不管在任何情况下得杀死进程的信号
* 由于iOS应用程序平台的限制，在iOS APP内禁止kill掉进程，所以一般不会处理

SIGABRT
SIGTRAP

* abnormal termination condition, as is e.g. initiated by abort()
* 通常由于异常引起的中断信号，异常发生时系统会调用abort()函数发出该信号
* iOS平台，一种是由于方法调用错误(调用了不能调用的方法)
* iOS平台，一种是由于数组访问越界的问题

SIGFPE

* erroneous arithmetic operation such as divide by zero
* 浮点数异常的信号通知
* 一般是由于 除数为0引起的

### 信号捕获不到的崩溃信息怎么收集？
>后台容易崩溃的原因是什么呢？如何避免后台崩溃？怎么去收集后台信号捕获不到的那些崩溃信息呢？还有哪些信号捕获不到的崩溃情况？怎样监控其他无法通过信号捕获的崩溃信息？
	
首先，我们来看第一个问题，**后台容易崩溃的原因是什么？**
iOS 后台保活的 5 种方式：Background Mode、Background Fetch、Silent Push、PushKit、Background Task.

* 使用 Background Mode 方式的话，App Store 在审核时会提高对 App 的要求。通常情况下，只有那些地图、音乐播放、VoIP 类的 App 才能通过审核。
* Background Fetch 方式的唤醒时间不稳定，而且用户可以在系统里设置关闭这种方式，导致它的使用场景很少。
* Silent Push 是推送的一种，会在后台唤起 App 30 秒。它的优先级很低，会调用 application:didReceiveRemoteNotifiacation:fetchCompletionHandler: 这个 delegate，和普通的 remote push notification 推送调用的 delegate 是一样的。
* PushKit 后台唤醒 App 后能够保活 30 秒。它主要用于提升 VoIP 应用的体验。
* Background Task 方式，是使用最多的。App 退后台后，默认都会使用这种方式。	
	
而 Background Task 这种方式，就是系统提供了 beginBackgroundTaskWithExpirationHandler 方法来延长后台执行时间，可以解决你退后台后还需要一些时间去处理一些任务的诉求	.

```
- (void)applicationDidEnterBackground:(UIApplication *)application {
    self.backgroundTaskIdentifier = [application beginBackgroundTaskWithExpirationHandler:^( void) {
        [self yourTask];
    }];
}
```
在这段代码中，yourTask 任务最多执行 3 分钟，3 分钟内 yourTask 运行完成，你的 App 就会挂起。 如果 yourTask 在 3 分钟之内没有执行完的话，系统会强制杀掉进程，从而造成崩溃，这就是为什么 App 退后台容易出现崩溃的原因.

再看看第二个问题：**如何避免后台崩溃呢？**
如果我们要想避免这种崩溃发生的话，就需要严格控制后台数据的读写操作。比如，你可以先判断需要处理的数据的大小，如果数据过大，也就是在后台限制时间内或延长后台执行时间后也处理不完的话，可以考虑在程序下次启动或后台唤醒时再进行处理。
App 退后台后，这种由于在规定时间内没有处理完而被系统强制杀掉的崩溃，是无法通过信号被捕获到的.	
	
那么，我们又应该**怎么去收集退后台后超过保活阈值而导致信号捕获不到的那些崩溃信息呢？**
>采用 Background Task 方式时，我们可以根据 beginBackgroundTaskWithExpirationHandler 会让后台保活 3 分钟这个阈值，先设置一个计时器，在接近 3 分钟时判断后台程序是否还在执行。如果还在执行的话，我们就可以判断该程序即将后台崩溃，进行上报、记录，以达到监控的效果

<font color=red size=4>还有哪些信号捕获不到的崩溃情况？怎样监控其他无法通过信号捕获的崩溃信息？ </font>
>其他捕获不到的崩溃情况还有很多，主要就是内存打爆和主线程卡顿时间超过阈值被 watchdog 杀掉这两种情况。
>其实，监控这两类崩溃的思路和监控后台崩溃类似，我们都先要找到它们的阈值，然后在临近阈值时还在执行的后台程序，判断为将要崩溃，收集信息并上报.(在后面文章分析)

<font color=red size=4>采集到崩溃信息后如何分析并解决崩溃问题呢？</font>
我们采集到的崩溃日志，主要包含的信息为：进程信息、基本信息、异常信息、线程回溯。

* 进程信息：崩溃进程的相关信息，比如崩溃报告唯一标识符、唯一键值、设备标识；
* 基本信息：崩溃发生的日期、iOS 版本；
* 异常信息：异常类型、异常编码、异常的线程；
* 线程回溯：崩溃时的方法调用栈。

方法调用栈顶，就是最后导致崩溃的方法调用.
一些被系统杀掉的情况，我们可以通过异常编码来分析,你可以在维基百科上，查看完整的异常编码。这里列出了 44 种异常编码，但常见的就是如下几种：

属性 | 说明
--------- | -------------
0x8badf00d | 表示 App 在一定时间内无响应而被 watchdog 杀掉的情况
0xdeadfa11 | ⽤用户强制退出(系统⽆无响应时,⽤用户按电源开关和HOME)
0xc00010ff | 因为太烫了被干掉
0xdead10cc | 因为在后台时仍然占据系统资源(⽐如通讯录)被干掉
`0x8badf00d` 这种情况是出现最多的。当出现被 watchdog 杀掉的情况时，我们就可以把范围控制在主线程被卡的情况。
`0xdeadfa11` 的情况，是用户的主动行为，我们不用太关注。
`0xc00010ff` 这种情况，就要对每个线程 CPU 进行针对性的检查和优化

