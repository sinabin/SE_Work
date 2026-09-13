# NOTE: Codex 이관용 사본. 원본의 평문 비밀정보는 환경변수/CHANGE_ME로 치환됨.
pdsh -g all '
    # 1. 호스트명 가져오기
    HOSTNAME=$(uname -n)
    
    # 2. 로직 테스트
    case "$HOSTNAME" in
        *"ccnweb"*)     # "ccnweb"이라는 글자가 들어가기만 하면 잡혀야 함
            CHECK_LIST="CHECK_WEB_TEST" ;;
            
        *"ccnprivacy"*)
            CHECK_LIST="CHECK_PRIVACY" ;;
            
        *"ccnstaters"*)
            CHECK_LIST="CHECK_STATERS" ;;
            
        *) 
            CHECK_LIST="CHECK_DEFAULT" ;;
    esac
    
    # 3. 결과 출력
    echo "HOST: $HOSTNAME  ---> SELECTED: $CHECK_LIST"
' | sort
