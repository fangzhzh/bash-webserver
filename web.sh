#!/bin/bash
base=$(dirname $0)


read request

declare -A headers
while /bin/true; do
    read header
    [ "$header" == $'\r' ] && break;
    IFS=":" read -a values <<< $header
    headers[${values[0]}]="${values[@]:1}"
done

declare -A cookies
if [ -n "${headers[Cookie]}" ]; then
    cookie_str="${headers[Cookie]}"
    IFS=';' read -a cookie_list <<< $cookie_str
    len=${#cookie_list[@]}
    for (( i=0; i<$len; i++ ))
    do
        line=${cookie_list[$i]}
        IFS='=' read -a pair <<< $line
        cookies[${pair[0]}]="${pair[1]}"
    done

fi

if [[ $request =~ ^GET ]]
then
    url="${request#GET }"
    method=get
else
    url="${request#POST }"
    method=post
fi
url="${url% HTTP/*}"

function static() {
    static_base=$base
    filename="$static_base$1"
    if [ -f "$filename" ]; then
        echo -e "HTTP/1.1 200 OK\r"
        echo -e "Content-Type: `/usr/bin/file -bi \"$filename\"`\r"
        echo -e "\r"
        cat "$filename"
    else
        echo -e "HTTP/1.1 404 Not Found\r"
        echo -e "Content-Type: text/html\r"
        echo -e "\r"
        echo -e "404 Not Found\r"
        echo -e "$url\r"
        echo -e "\r"
    fi
}

function set_session_cache() {
    echo $@ >> /tmp/entry.cache
}
function get_session_cache() {
    sessionid=$(echo $1 | tr '\r' ' ')
    [ -n "$sessionid" ] && grep "$sessionid" /tmp/entry.cache
}
function invalidate_cache() {
    sessionid=$(echo $1 | tr '\r' ' ')
    sed -e "/^$sessionid/d" -i /tmp/entry.cache

}

function login() {
    if [ "$method" == "post" ]
    then
        content_length=${headers["Content-Length"]}
        content_length=$(echo $content_length | tr '\r' ' ')
        post_str=$(head -c $content_length)

        declare -A POST
        IFS="&" read -a post_param <<< "$post_str"
        len=${#post_param[@]}
        for (( i=0; i<$len; i++ ))
        do
            line=${post_param[$i]}
            IFS='=' read -a pair <<< $line
            POST[${pair[0]}]="${pair[1]}"
        done
        username=${POST[username]}
        password=${POST[password]}
        result=$(echo "select username, profile from users where username=\"$username\" and password=password(\"$password\")" | mysql -u entry_user -h 203.117.172.31 -pentry_password -D entry_task 2>/dev/null | tail -n 1)
        if [ -n "$result" ]
        then
            session_key=$(uuidgen)
            set_session_cache $session_key $result
            echo -e "HTTP/1.1 302 Found\r"
            echo -e "Set-Cookie: sessionid=${session_key}\r"
            echo -e "Location: /\r"
            echo -e "\r"
        else
            echo -e "HTTP/1.1 403 Forbidden\r"
            echo -e "\r"
        fi
    else
        static /templates/login.html
    fi
}

function logout_() {
    sessionid=${cookies[sessionid]}
    session=$(get_session_cache "$sessionid")
    if [ -n "$session" ]
    then
        invalidate_cache $sessionid
    fi
    echo -e "HTTP/1.1 302 Found\r"
    echo -e "Location: /\r"
    echo -e "\r"
}

function upload() {
    sessionid=${cookies[sessionid]}
    session=$(get_session_cache "$sessionid")
    read -a list <<< $session
    username=${list[1]}
    upload_base=$base/static/profile
    if [ -z "$session" ]; then
        echo -e "HTTP/1.1 302 Found\r"
        echo -e "Location: /login\r"
        echo -e "\r"
    else
        if [ $method == "get" ]; then
            echo -e "HTTP/1.1 405 Method Not Allowed\r"
            echo -e "\r"
        else
            echo -e "HTTP/1.1 100 Continue\r"
            echo -e "\r"
            content="${headers['Content-Type']}"
            length="${headers['Content-Length']}"
            boundary=${content#multipart/form-data; boundary=}
            separator=--$boundary
            end_separator=$separator--
            sofar=0
            length=$(echo $length | tr '\r' ' ')
            left=$length

            while true
            do
                read line
                left=$(expr $left \- ${#line} \- 1)
                [ "$line" == $'\r' ] && break
            done

            uuid=$(uuidgen)

            upload_file_size=$(expr $left \- ${#end_separator} \- 3)
            head -c $upload_file_size > $upload_base/$uuid
            head -c $(expr ${#end_separator} + 3) > /dev/null
            # update db
            echo "update users set profile=\"$uuid\" where username=\"$username\"" | mysql -u entry_user -h 203.117.172.31 -pentry_password -D entry_task 2>/dev/null
            # purge
            invalidate_cache $sessionid
            result=$(echo "select username, profile from users where username=\"$username\"" | mysql -u entry_user -h 203.117.172.31 -pentry_password -D entry_task 2>/dev/null | tail -n 1)
            session_key=$(echo $sessionid | tr '\r' ' ')
            set_session_cache $session_key $result

            printf "HTTP/1.1 302 Found\r\n"
            printf "Content-Type: text/plain\r\n"
            printf "Location: /\r\n"
            printf "\r\n"
        fi
    fi
}


function home() {
    sessionid=${cookies[sessionid]}
    session=$(get_session_cache "$sessionid")
    read -a list <<< $session
    username=${list[1]}
    image=${list[2]}
    if [ "$image" = "NULL" ];
    then
        image='default.png'
    fi
    if [ -z "$session" ]; then
        echo -e "HTTP/1.1 302 Found\r"
        echo -e "Location: /login\r"
        echo -e "\r"
    else
        echo -e "HTTP/1.1 200 OK\r"
        echo -e "Content-Type: text/html\r"
        echo -e "\r"
        sed -e "s/USERNAME/${username}/g" -e "s/PROFILEIMG/${image}/g" $base/templates/index.html
    fi
}

function application() {
    url=$1
    case $url in
        "/")
            home ;;
        "/login")
            login ;;
        "/logout")
            logout_ ;;
        "/upload")
            upload ;;
    esac
}

if [[ $url =~ ^/static/ ]]
then
    static $url
else
    application $url
fi
