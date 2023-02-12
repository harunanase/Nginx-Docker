# Env image
FROM alpine AS base

ARG NGINX_FILE=1.22.1
ARG NGX_GEOIP2_VER=3.4
ARG MODSECURITY_VER=v3/master
ARG MODSECURITY_NGINX_VER=v1.0.3

# Nginx compile options
ENV accessLogPath=/opt/nginx/logs/access.log
ENV errorLogPath=/opt/nginx/logs/error.log
ENV pidPath=/opt/nginx/tmp/nginx.pid
ENV lockPath=/opt/nginx/tmp/nginx.lock
ENV prefix=/opt/nginx
ENV nginxUser=www
ENV nginxGroup=www

# ModSecurity option
ENV modsecurityPrefix=/opt/modsecurity
ENV MODSECURITY_INC="${modsecurityPrefix}/include/"
ENV MODSECURITY_LIB="${modsecurityPrefix}/lib/"

ENV NGINX_NAME=haru7se

# Builder image
FROM base AS builder
WORKDIR /build

# install requirements
RUN apk add --no-cache curl git g++ pcre-dev zlib-dev linux-headers openssl-dev libmaxminddb-dev geoip-dev libtool make automake autoconf && rm -rf /var/cache/apk/*

# download geoip2 module
RUN curl -L -O https://github.com/leev/ngx_http_geoip2_module/archive/refs/tags/${NGX_GEOIP2_VER}.tar.gz
RUN mkdir -p /build/ngx_geoip2 && tar zxf ${NGX_GEOIP2_VER}.tar.gz -C /build/ngx_geoip2 --strip-components 1

# download and compile ModSecurity
#RUN curl -L -O https://github.com/SpiderLabs/ModSecurity/archive/refs/tags/${MODSECURITY_VER}.tar.gz
RUN mkdir -p /build/ && cd /build && git clone https://github.com/SpiderLabs/ModSecurity && \
		cd ModSecurity && git checkout ${MODSECURITY_VER}
RUN cd /build/ModSecurity && sh ./build.sh && git submodule init && git submodule update && ./configure --prefix ${modsecurityPrefix} && make -j$(nproc) && make install

# download ModSecurity-nginx
RUN curl -L -O https://github.com/SpiderLabs/ModSecurity-nginx/archive/refs/tags/v1.0.3.tar.gz
RUN mkdir /build/modsecurity-nginx && tar zxf ${MODSECURITY_NGINX_VER}.tar.gz -C /build/modsecurity-nginx --strip-components 1

RUN curl -L -O https://nginx.org/download/nginx-${NGINX_FILE}.tar.gz && \
    tar zxf nginx-${NGINX_FILE}.tar.gz && \
        rm nginx-${NGINX_FILE}.tar.gz

WORKDIR /build/nginx-${NGINX_FILE}
RUN sed -i "49s/Server: nginx/Server: ${NGINX_NAME}/" ./src/http/ngx_http_header_filter_module.c && \
		sed -i "50s/Server: \" NGINX_VER/Server: ${NGINX_NAME}\"/" ./src/http/ngx_http_header_filter_module.c && \
		sed -i "22s/NGINX_VER/\"${NGINX_NAME}\"/" ./src/http/ngx_http_special_response.c && \
		sed -i "29s/NGINX_VER_BUILD/\"${NGINX_NAME}\"/" ./src/http/ngx_http_special_response.c && \
		sed -i "36s/nginx/${NGINX_NAME}/" ./src/http/ngx_http_special_response.c

RUN ./configure --prefix=${prefix} --error-log-path=${errorLogPath} --http-log-path=${accessLogPath} \
		--pid-path=${pidPath} --lock-path=${lockPath} --with-file-aio --with-stream \
        --with-http_ssl_module --with-http_v2_module --with-http_realip_module \
        --with-http_sub_module --with-http_gunzip_module --with-http_gzip_static_module \
        --with-http_stub_status_module --with-stream_ssl_module --with-stream_realip_module \
		--with-stream_geoip_module --with-http_geoip_module \
		--with-ld-opt="-Wl,-rpath,${LUAJIT_LIB}" \
            --user=${nginxUser} --group=${nginxGroup} \
			--add-dynamic-module=/build/ngx_geoip2 \
			--add-dynamic-module=/build/modsecurity-nginx --with-compat
RUN make -j$(nproc) && make install

RUN sed -i '11i load_module ./modules/ngx_http_geoip2_module.so;' ${prefix}/conf/nginx.conf && \
		sed -i '12i load_module ./modules/ngx_stream_geoip2_module.so;' ${prefix}/conf/nginx.conf && \
		sed -i '13i load_module ./modules/ngx_http_modsecurity_module.so;' ${prefix}/conf/nginx.conf

# Final image
FROM base
RUN apk add --no-cache pcre-dev zlib-dev openssl-dev libmaxminddb-dev geoip-dev && rm -rf /var/cache/apk/*
COPY --from=builder ${prefix} ${prefix}
COPY --from=builder ${modsecurityPrefix} ${modsecurityPrefix}
RUN addgroup -g 1000 -S ${nginxGroup} && adduser -u 1000 -S -G ${nginxGroup} ${nginxUser}

CMD ["/opt/nginx/sbin/nginx", "-g", "daemon off;"]
