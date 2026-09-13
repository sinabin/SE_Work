# NOTE: Codex 이관용 사본. 원본의 평문 비밀정보는 환경변수/CHANGE_ME로 치환됨.
#!/bin/bash

AG1=$1
AG2=$2

COMMAND(){
	echo -e "\nusage: 1372_system_check [option]"
	echo -e "\n\t\033[1;34m-h | --help\033[m)\t\t Show how to use"
	echo -e "\t\033[1;34m-l | --list\033[m)\t\t Show information of hosts"
	echo -e "\t\033[1;34m-g | --group\033[m)\t\t Show group of hosts in pdsh"
	echo -e "\t\033[1;34m-t | --type\033[m)\t\t Show the system check list"
	
}
HOSTLIST(){
	echo -e "\nusage: 1372_system_check { all | group | hostname } { all | type }\n"
	cat /etc/hosts | grep -v -e localhost -e \# -e \^$
}
USAGE(){
	echo -e "\nusage: 1372_system_check { all | group | hostname } { all | type }\n"
	echo -e "   ex) 1372_system_check all all\t\t ### Check all status of all systems"
	echo -e "   ex) 1372_system_check ccnwas1 all\t\t ### Check all status of was server #1"
	echo -e "   ex) 1372_system_check rec cpu\t\t ### Check cpu status of rec group"
	echo -e "   ex) 1372_system_check ccndb1 disk\t\t ### Check disk status of db server #1"
}

DSHGROUP(){	
	
		echo -e "\nusage: 1372_system_check { all | group | hostname } { all | type }\n"
		DSH_DIR="/etc/dsh/group"
		COUNT=0
		MYSQL_PWD="$LEGACY_DB_PASS" mysql -u "${LEGACY_DB_USER:-CHANGE_ME}" -D "${LEGACY_DB_NAME:-CHANGE_ME}" -e "truncate dshgroup" 2> /dev/null
		for DL in `ls $DSH_DIR`
		do
			COUNT=$((COUNT+1))
			DHS_CEN=`cat $DSH_DIR/$DL`
			DSH_H=`echo $DHS_CEN | sed 's/ /,/g'`
			DSH_G=`echo "$DL"`
            MYSQL_PWD="$LEGACY_DB_PASS" mysql "${LEGACY_DB_NAME:-CHANGE_ME}" << EOF
			insert into dshgroup (Num,DshGroup,DshHostname) values ('$COUNT', '$DSH_G', '$DSH_H');
EOF
		done
		MYSQL_PWD="$LEGACY_DB_PASS" mysql -u "${LEGACY_DB_USER:-CHANGE_ME}" -D "${LEGACY_DB_NAME:-CHANGE_ME}" -e "select * from dshgroup" 2> /dev/null
}
CHECK_TYPE(){
		
		echo -e "\nusage: 1372_system_check { all | group | hostname } { all | type }\n"
		MYSQL_PWD="$LEGACY_DB_PASS" mysql -u "${LEGACY_DB_USER:-CHANGE_ME}" -D "${LEGACY_DB_NAME:-CHANGE_ME}" -e "truncate checklist" 2> /dev/null
		CHECK_LIST="all cpu disk memory process service"
		for CL in `echo "$CHECK_LIST"`
		do
            MYSQL_PWD="$LEGACY_DB_PASS" mysql "${LEGACY_DB_NAME:-CHANGE_ME}" << EOF
			insert into checklist (typelist) values ('$CL');
EOF
		done
		MYSQL_PWD="$LEGACY_DB_PASS" mysql -u "${LEGACY_DB_USER:-CHANGE_ME}" -D "${LEGACY_DB_NAME:-CHANGE_ME}" -e "select * from checklist" 2> /dev/null
}



if [ $# -eq 0 ]; then
	COMMAND
	exit 1
fi

case $AG1 in
	-h | --help)
			USAGE
			exit 1	
			;;
	

	-l | --list)
			HOSTLIST
			exit 1
			;;

	-g | --group)
			DSHGROUP
			exit 1

			;;

	-t | --type)
			CHECK_TYPE
			exit 1
			;;
	all)
		echo "add vg[1-2]"
		echo "pdsh -g all \"echo 1\""
		;;

	*)
		A=`cat /etc/hosts | grep -w -q "$AG1"; echo $?`
	
		if [ $A -eq 0 ]; then

			if [ $# -ne 2 ]; then

				echo -e "\n\033[1;31mtype is incorrect. \033[mUse option -t or --type"
				COMMAND
				exit 1

			fi

			case $AG2 in

				all)
					echo "all"
					;;

				cpu)
					echo "cpu"
					;;

				disk)
					echo "disk"
					;;

				memory)
					echo "memory"
					;;

				process)
					echo "process"
					;;

				service)
					echo "service"
					;;

				*)
					echo -e "\n\033[1;31mtype is incorrect. \033[mUse option -t or --type"
					COMMAND
					exit 1
					;;
			esac
		else
			echo -e "\n\033[1;31mhostname is incorrect. \033[mUse option -l or --list"
			COMMAND
			exit 1
		fi
	;;
esac
