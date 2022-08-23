#/bin/bash
#设计思路是，创建每个程序对应的启动路径的文件，重启某个程序时，先读取文件，无文件则创建并写入，可以减少每次重启时的执行的脚本命令

#先查看文件是否存在且是否为空
#后查看进程是否存在
#根据以上两个结果确定重启方式

_findPIDstatus(){
	pidnum=`ps -ef | grep $1 | grep -v grep | awk '{print $2}'`
	if [ -z $pidnum ];then
		echo 0
	else
		echo $pidnum	
	fi
}

#参数1-搜索到的路径
#参数2-写入路径的文件名，绝对路径
#参数3-启动文件名
#参数4-程序进程名
#参数5-写入文件内容
_yesorno(){
	rm -rf $2
	echo -e "系统搜索到的路径：" "\033[32;40;1m[\033[0m" $1 "\033[32;40;1m]\033[0m"
	read -p "请确认路径是否正确，是否要重启？[y/n]：" p
	if [[ $p == "y" ]];then
		if [ `_findPIDstatus $4 ` -ne 0 ];then
			ps -ef | grep $4 | grep -v grep | awk '{print $2}' | xargs kill -9
		fi
		#确认则将路径写入tomcat路径文件，方便下次重启，并杀死tomcat进程，并进入该路径重新启动tomcat
		echo $5 >> $2
		echo -e "\033[32;40;1m [路径确认，开始重新启动] \033[0m"
		cd $1
		if [ -L $1"/"$3 ];then
			./$3
			sleep 7
		else
			#非可执行文件，即为tomcat路径，添加/bin路径后，直接执行startup.sh
			cd $1"bin"
			sh startup.sh
		fi
	else
		echo -e "\033[31;40;1m [人工确认路径错误，路径文件已删除，请手动重启] \033[0m"
	fi	
}

#对比函数(0正确，1不正确)
_contrast(){
	if [[ $1 == $2 ]];then
		echo "0";
	else    
		echo "1";
	fi
}

#重启tomcat===================================================================================================================
_restarttomcat(){
	#判断是否存在文件且是否为空
	if [ -s /home/restarttomcatpath.txt ];then
		echo -e "\033[32;40;1m restarttomcatpath文件存在且不为空，读取文件重启 \033[0m"
		tomcatpath=`cat /home/restarttomcatpath.txt`
		_yesorno $tomcatpath /home/restarttomcatpath.txt "" tomcat $tomcatpath
	else
		rm -rf /home/restarttomcatpath.txt
		if [ `_findPIDstatus tomcat` -eq 0 ];then
			echo -e "\033[32;40;1m restarttomcatpath文件不存在或为空，tomcat进程已停止，使用搜寻日志文件方式寻找路径重启 \033[0m"
			_findtomcatlogpathrestart
		else
			echo -e "\033[32;40;1m restarttomcatpath文件不存在或为空，tomcat进程未停止，根据进程自动寻找路径重启 \033[0m"
			_findrestarttomcatpath
		fi
	fi
}

_findtomcatlogpathrestart(){
	#logdate=$(expr `date +%Y_%m_%d`)
	#使用tomcat catalina.out日志为锚点，使用find命令搜索此文件，找到tomcat路径，并寻找路径下是否有emp项目
	tomcatlogpath=`find / -name catalina.out`
	tomcatpath=`echo ${tomcatlogpath%logs*}`
	if [ $(find $tomcatpath"webapps/" -name SystemGlobals.properties) ];then
		_yesorno $tomcatpath /home/restarttomcatpath.txt "" tomcat $tomcatpath
	else
		echo -e "\033[31;40;1m [目录 ‘$tomcatpath’ 下未找到emp，请手动寻找路径重启] \033[0m"
	fi
}

_findrestarttomcatpath(){
	#使用ps查找tomcat进程，并获取路径
	stringtomcat=`ps -ef | grep tomcat | grep -v grep`
	#获取tomcat路径,先删除左边第一个=号及之前的字符
	stringtomcatL=`echo ${stringtomcat#*=}`
	#再删除右边第一个conf及之后的字符
	stringtomcatR=`echo ${stringtomcatL%%conf*}`
	#stringtomcatR即为最终的tomcat路径
	#使用find命令查找startup.sh文件路径，如有多个路径则循环执行后续步骤，否则单独执行，并去掉bin路径，与stringtomcatR交叉对比，避免文件路径出错，对比成功即为当前系统中运行的tomcat路径
	#新增一个文件
	#搜索内容写入至该文件(搜索到的文件路径可能不止一个)
	find / -name startup.sh >> /home/startup.txt

	#获取文件行数
	num=`cat /home/startup.txt | wc -l`
	#最终判断路径字符串是否正确(0正确，1不正确)
	finalnum=0
	#判断find搜索出来的是多个路径还是单个路径
	if [[ $num -gt 1 ]];then
		#多个路径，根据行数逐一进行判断
		for((i=$num;i>0;i--))
		do
			#获取第i行路径
			tempstr=`awk 'NR=='$i' {print}' /home/startup.txt`
			#去掉路径中的bin路径，因为根据进程查询出来的路径没有bin，需要去掉bin进行对比
			tempstrR=`echo ${tempstr%%bin*}`
			#对比结果写入finalnum，0相同，1不相同
			finalnum=`_contrast $stringtomcatR $tempstrR`
			#判断是否相同，相同则跳出循环
			if [[ $finalnum -eq 0 ]];then
				break;
			fi
		done
	else
		#单个路径，直接处理
		tempstr=`awk '{print}' /home/startup.txt`
		tempstrR=`echo ${tempstr%%bin*}`
		finalnum=`_contrast $stringtomcatR $tempstrR`
	fi

	if [[ $finalnum -eq 0 ]];then
		#判断最终路径是否匹配，匹配则提示路径，并选择是否重启
		_yesorno $stringtomcatR /home/restarttomcatpath.txt "" tomcat $stringtomcatR
	else
		echo -e "\033[31;40;1m [路径不匹配，请手动重启] \033[0m"
	fi
	#删除搜索到的所有tomcat路径的文件
	rm -rf /home/startup.txt
}


#选择重启项
echo -e "请选择重启项目：\n 1)tomcat\n 2)\n 4)"
read -p "输入对应程序数字之和，(如重启tomcat+则输入5)：" sumnum
#数字之和共7种，1-tomcat，7全部重启
case $sumnum in
	1)
		_restarttomcat
	;;
	2)
		
	;;
	3)
		_restarttomcat
		
	;;
	4)
		
	;;
	5)
		_restarttomcat
		
	;;
	6)
		
		
	;;
	7)
		_restarttomcat
		
		
	;;
	*)
		echo -e "\033[31;40;1m [输入不合法，已退出程序，请重新运行] \033[0m"
	;;
esac

ps -ef | grep tomcat | grep -v grep


