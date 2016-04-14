#!/bin/bash
base=/home/ducheng/entry


read request

declare -A headers
while /bin/true; do
    read header
    [ "$header" == $'\r' ] && break;
    values=(${header//:/})
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
    static_base=/home/ducheng/entry
    filename="$static_base$1"
    if [ -f "$filename" ]; then
        echo -e "HTTP/1.1 200 OK\r"
        echo -e "Content-Type: `/usr/bin/file -bi \"$filename\"`\r"
        echo -e "\r"
        cat "$filename"
        echo -e "\r"
    else
        echo -e "HTTP/1.1 404 Not Found\r"
        echo -e "Content-Type: text/html\r"
        echo -e "\r"
        echo -e "404 Not Found\r"
        echo -e "$url\r"
        echo -e "\r"
    fi
}

function login() {
    echo -e "HTTP/1.1 200 OK\r"
    echo -e "Content-Type: application/json\r"
    echo -e "Set-Cookie: sessionid=haha"
    echo -e "Set-Cookie: testing=ok str"
    echo -e "\r"
    echo -e "{\"login\":\"ok\"}"
    echo -e "\r"
}

function upload() {
    if [ $method == "get" ]; then
        echo -e "HTTP/1.1 405 Method Not Allowed\r"
        echo -e "\r"
    else
        content="OK haha"
        echo -e "HTTP/1.1 200 OK\r"
        echo -e "Content-Type: text/plain\r"
        echo -e "Content-Length: ${#content}\r"
        echo -e "\r"
        echo -e $content
        echo -e "\r"
    fi
}

function application() {
    url=$1
    case $url in
        "/")
            static /templates/index.html;;
        "/login")
            login ;;
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
