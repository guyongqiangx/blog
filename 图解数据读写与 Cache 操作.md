# 图解数据读写与 Cache 操作



高速缓存（Cache）主要是为了解决CPU运算速度与内存（Memory）读写速度不匹配的矛盾而存在， 是CPU与内存之间的临时存贮器，容量小，但是交换速度比内存快。

> 百度百科是这样介绍缓存读取的：
>   CPU要读取一个数据时，首先从Cache中查找，如果找到就立即读取并送给CPU处理；如果没有找到，就用相对慢的速度从内存中读取并送给CPU处理，同时把这个数据所在的数据块调入Cache中，可以使得以后对整块数据的读取都从Cache中进行，不必再调用内存。
>   正是这样的读取机制使CPU读取Cache的命中率非常高（大多数CPU可达90%左右），也就是说CPU下一次要读取的数据90%都在Cache中，只有大约10%需要从内存读取。这大大节省了CPU直接读取内存的时间，也使CPU读取数据时基本无需等待。总的来说，CPU读取数据的顺序是先Cache后内存。

  Cache的硬件实现中通常包含一级Cache（L1 Cache），二级Cache（L2 Cache）甚至多级Cache；对于一级Cache，又有I-Cache（指令缓存）和D-Cache（数据缓存）之分，本文准备不讨论各级Cache的区别以及I-Cache和D-Cache的细节，仅将这些所有实现笼统称为Cache。
  本文仅针对Cache的读写进行简单说明并通过示意图演示什么时候需要写回（flush）缓存，什么时候需要作废（Invalidate）缓存。
  对于指令缓存的I-Cache和数据缓存的D-Cache，平时D-Cache访问比较多，以下主要讨论数据访问的D-Cache，指令缓存I-Cache原理一样。
　　

![Cache读写原理](https://img-blog.csdnimg.cn/img_convert/10bbcd7fdd466a55cb5e34f2c9f77892.png)
图一、Cache读写原理
　　
写入数据时：

第一步，CPU将数据写入Cache；
第二步，将Cache数据传送到Memory中相应的位置；

读取数据时：

第一步，将Memory中的数据传送到Cache中；
第二步，CPU从Cache中读取数据；

在具体的硬件实现上，Cache有写操作有透写（Write-Through）和回写（Write-Back）两种方式：

在透写式Cache中，CPU的数据总是写入到内存中，如果对应内存位置的数据在Cache中有一个备份，那么这个备份也要更新，保证内存和Cache中的数据永远同步。所以每次操作总会执行图一中的步骤1和2。

在回写式Cache中，把要写的数据只写到Cache中，并对Cache对应的位置做一个标记，只在必要的时候才会将数据更新到内存中。所以每次写操作都会执行步骤中的图1，但并不是每次执行步骤1后都执行步骤2操作。

透写方式存在性能瓶颈，性能低于回写方式，现在的CPU设计基本上都是采用Cache回写方式。

通常情况下，数据只通过CPU进行访问，每次访问都会经过Cache，此时数据同步不会有问题。

在有设备进行DMA操作的情况下，设备读写数据不再通过Cache，而是直接访问内存。在设备和CPU读写同一块内存时，所取得的数据可能会不一致，如图二。
　　
![设备和CPU读写同一块内存时数据不一致](https://img-blog.csdnimg.cn/img_convert/180818d03beb254e7230e92f8abf367a.png)

图二、设备和CPU读写同一块内存时数据不一致

CPU执行步骤1将数据A写入Cache，但并不是每次都会执行步骤2将数据A同步到内存，导致Cache中的数据A和内存中的数据A’不一致；步骤3中，外部设备通过DMA操作时直接从内存访问数据，从而取得的是A’而不是A。
设备DMA操作完成后，通过步骤4将数据B写入内存；但是由于内存中的数据不会和Cache自动进行同步，步骤5不会被执行，所以CPU执行步骤3读取时数据时，获取的可能是Cache中的数据B’，而不是内存中的数据B；

在CPU和外设访问同一片内存区域的情况下，如何操作Cache以确保设备和CPU访问的数据一致就显得尤为重要，见图三。

![Cache操作同步数据](https://img-blog.csdnimg.cn/img_convert/e6708618b296a3cc8d86e537c07f4f07.png)
图三、Cache操作同步数据

CPU执行步骤1将数据A写入Cache，由于设备也需要访问数据A，因此执行步骤2将数据A通过flush 操作同步到内存；步骤3中，外部设备通过DMA操作时直接从内存访问数据A，最终CPU和设备访问的都是相同的数据。

设备DMA操作完成后，通过步骤4将数据B写入内存；由于CPU也需要访问数据B，访问前通过invalidate操作作废Cache中的数据，从而通过Cache读取数据时Cache会从内存取数据，所以CPU执行步骤6读取数据时，获取到的是从内存更新后的数据；

Cache操作举例：
1. 外部设备I/O和DMA传输。

例如，在博通机顶盒平台中，内存加解密在单独的安全芯片中进行，安全芯片访问的数据通过DMA进行传输操作。因此，在进行内存加解密前，需要flush D-Cache操作将数据同步到到内存中供安全芯片访问；加解密完成后需要执行invalidate D-Cache操作，以确保CPU访问的数据是安全芯片加解密的结果，而不是Cache之前保存的数据；

DMA进行数据加解密的示例代码：
```c
void mem_dma_desc(
		unsigned long Mode,
		unsigned long SrcAddr, /* input data addr */
		unsigned long DestAddr, /* output data addr */
		unsigned long Slot,
		unsigned long Size) /* dma data size */
	{
		...prepare for dma encryption/decryption operation...

		/* flush data in SrcAddr from D-Cache to memory 
		   to ensure dma device get the correct data */
		flush_d_cache(SrcAddr, Size);

		...do dma operation, output will be redirect to DestAddr...
	
		/* invalidate D-Cache to ensure fetch data from memory
		   instead of cached data in D-Cache */
		invalidate_d_cache(DestAddr, Size);
		return;
	}

```

nand flash的控制器也支持DMA读取的方式。在数据向nand flash写入数据时需要先flash dcache确保DMA操作的数据是真实要写如的数据，而不是内存中已经过期的数据；从nand flash读取数据后需要invalidate dcache，使cache中的数据失效，从而确保cpu读取的是内存数据，而不是上一次访问时缓存的结果。

nand flash 通过DMA方式读取数据的示例代码：

```c
static int nand_dma_read(
			struct nand_dev *nand,
			uint64_t addr, /* read addr */
			void *buf,     /* output buffer */
			size_t len)
{
	int ret;

	...prepare for nand flash read and device dma transfer...

	/* flush dma descriptor for nand flash read operation */
	flush_d_cache(descs, ndescs * sizeof(*descs));

	/* nand flash dma read operation */
	ret = nand_dma_run(nand, (uintptr_t)descs);

	/* invalidate read output buffer to ensure fetch data from memory
	   instead of cached data in D-Cache */
	invalidate_d_cache(buf, len);

	...other operations...
	
	return ret;
}
```

2. 通常Cache分为I-Cache和D-Cache，取指令时访问I-Cache，读写数据时访问D-Cache。

如果一段代码保存在外设（如nand  flash或硬盘）上，CPU想执行这段代码，需要先将这段代码作为数据复制到内存再将这段代码作为指令执行。由于写入数据和读取指令分别通过D-Cache和I-Cache，所以需要同步D-Cache和I-Cache，即复制后需要先将D-Cache写回到内存，而且还需要作废当前的I-Cache以确保执行的是Memory内更新的代码，而不是I-Cache中缓存的数据，如图四所示：

![CPU复制代码后再执行](https://img-blog.csdnimg.cn/img_convert/5ebdf9d609e2ca0c8e6c1dca7df8a5fe.png)
图四、CPU复制代码后执行

CPU复制代码后执行的示例代码：

```c
void copy_code_and_execution(
		unsigned char *src, 
		unsigned char *dest, 
		size_t len)
{
	...copy code from src addr to dest addr...

	/* flush instructions data in D-Cache to memory */
	flush_all_d_cache();

	/* invalidate I-Cache to ensure fetch instructions from memory
	   instead of cached data in I-Cache */
	invalidate_all_i_cache();

	...jump to dest address for execution and never return...

	/* actually it never reach here if it jumps to dest successfully */
	printf("failed to jumping...\r\n");

	return; 
}
```