# Env image
FROM alpine:3.13 AS base

ARG NGINX_FILE=1.19.3
ARG LUAJIT_VER=v2.1-20220411
ARG NGX_DEVEL_KIT_VER=v0.3.1
ARG NGX_LUA_VER=v0.10.21
ARG LUA_RESTY_CORE_VER=v0.1.23
ARG LUA_RESTY_LRUCACHE_VER=v0.13
ARG NGX_GEOIP2_VER=3.4

# Nginx compile options
ENV accessLogPath=/opt/nginx/logs/access.log
ENV errorLogPath=/opt/nginx/logs/error.log
ENV pidPath=/opt/nginx/tmp/nginx.pid
ENV lockPath=/opt/nginx/tmp/nginx.lock
ENV prefix=/opt/nginx
ENV nginxUser=www
ENV nginxGroup=www

# Lua compile option
ENV luajit2Prefix=/opt/luajit2
ENV LUAJIT_LIB=${luajit2Prefix}/lib
ENV LUAJIT_INC=${luajit2Prefix}/include/luajit-2.1

ENV NGINX_NAME=haru7se

# Builder image
FROM base AS builder
WORKDIR /build

# install requirements
RUN apk add --no-cache curl g++ pcre-dev zlib-dev linux-headers openssl-dev libmaxminddb-dev geoip-dev make && rm -rf /var/cache/apk/*

# download and compile luajit2
RUN curl -L -O https://github.com/openresty/luajit2/archive/refs/tags/${LUAJIT_VER}.tar.gz
RUN mkdir -p /build/luajit2 && tar zxf ${LUAJIT_VER}.tar.gz -C /build/luajit2 --strip-components 1
RUN cd luajit2 && make -j$(nproc) && make install PREFIX=${luajit2Prefix}

# download ngx_devel_kit
RUN curl -L -O https://github.com/vision5/ngx_devel_kit/archive/refs/tags/${NGX_DEVEL_KIT_VER}.tar.gz
RUN mkdir -p /build/ngx_devel_kit && tar zxf ${NGX_DEVEL_KIT_VER}.tar.gz -C /build/ngx_devel_kit --strip-components 1

# download ngx_lua
RUN curl -L -O https://github.com/openresty/lua-nginx-module/archive/refs/tags/${NGX_LUA_VER}.tar.gz
RUN mkdir -p /build/ngx_lua && tar zxf ${NGX_LUA_VER}.tar.gz -C /build/ngx_lua --strip-components 1

# download lua-resty-core
RUN curl -L -O https://github.com/openresty/lua-resty-core/archive/refs/tags/${LUA_RESTY_CORE_VER}.tar.gz
RUN mkdir -p /build/lua_resty_core && tar zxf ${LUA_RESTY_CORE_VER}.tar.gz -C /build/lua_resty_core --strip-components 1

# download lua-resty-lrucache
RUN curl -L -O https://github.com/openresty/lua-resty-lrucache/archive/refs/tags/${LUA_RESTY_LRUCACHE_VER}.tar.gz
RUN mkdir -p /build/lua_resty_lrucache && tar zxf ${LUA_RESTY_LRUCACHE_VER}.tar.gz -C /build/lua_resty_lrucache --strip-components 1

# download geoip2 module
RUN curl -L -O https://github.com/leev/ngx_http_geoip2_module/archive/refs/tags/${NGX_GEOIP2_VER}.tar.gz
RUN mkdir -p /build/ngx_geoip2 && tar zxf ${NGX_GEOIP2_VER}.tar.gz -C /build/ngx_geoip2 --strip-components 1

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
                    --user=${nginxUser} --group=${nginxGroup} \
			--with-stream_geoip_module --with-http_geoip_module \
				--with-ld-opt="-Wl,-rpath,${LUAJIT_LIB}" \
					--add-dynamic-module=/build/ngx_devel_kit \
					--add-dynamic-module=/build/ngx_lua \
					--add-dynamic-module=/build/ngx_geoip2
RUN make -j$(nproc) && make install

RUN cd /build/lua_resty_core && make -j$(nproc) && make install PREFIX=${prefix} && \
		cd /build/lua_resty_lrucache && make -j$(nproc) && make install PREFIX=${prefix} && \
		rm -rf /build

RUN sed -i "20i \ \ \ \ lua_package_path \"${prefix}/lib/lua/?.lua;;\";" ${prefix}/conf/nginx.conf && \
		sed -i '11i load_module ./modules/ndk_http_module.so;' ${prefix}/conf/nginx.conf && \
		sed -i '12i load_module ./modules/ngx_http_lua_module.so;' ${prefix}/conf/nginx.conf && \
		sed -i '13i load_module ./modules/ngx_http_geoip2_module.so;' ${prefix}/conf/nginx.conf && \
		sed -i '14i load_module ./modules/ngx_stream_geoip2_module.so;' ${prefix}/conf/nginx.conf

# Final image
FROM base
RUN apk add --no-cache pcre-dev zlib-dev openssl-dev libmaxminddb-dev geoip-dev && rm -rf /var/cache/apk/*
COPY --from=builder ${prefix} ${prefix}
COPY --from=builder ${luajit2Prefix} ${luajit2Prefix}
RUN addgroup -g 1000 -S ${nginxGroup} && adduser -u 1000 -S -G ${nginxGroup} ${nginxUser}

CMD ["/opt/nginx/sbin/nginx", "-g", "daemon off;"]
