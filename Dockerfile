FROM debian:jessie

# add our user and group first to make sure their IDs get assigned consistently, regardless of whatever dependencies get added
RUN groupadd -r mongodb && useradd -r -g mongodb mongodb



RUN apt-get update \
  && apt-get install -y curl numactl \
  && rm -rf /var/lib/apt/lists/* \
  && apt-get install -y libssl1.0.0 libssl-dev
RUN cd /lib/x86_64-linux-gnu \
    && ln -s libssl.so.1.0.0 libssl.so.10 \
    && ln -s libcrypto.so.1.0.0 libcrypto.so.10 \
    && ln -s /lib/x86_64-linux-gnu/libssl.so.1.0.0 /usr/lib/libssl.so.10 \
    && ln -s /lib/x86_64-linux-gnu/libcrypto.so.1.0.0 /usr/lib/libcrypto.so.10

# grab gosu for easy step-down from root
RUN gpg --keyserver pool.sks-keyservers.net --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4
RUN curl -o /usr/local/bin/gosu -SL "https://github.com/tianon/gosu/releases/download/1.2/gosu-$(dpkg --print-architecture)" \
  && curl -o /usr/local/bin/gosu.asc -SL "https://github.com/tianon/gosu/releases/download/1.2/gosu-$(dpkg --print-architecture).asc" \
  && gpg --verify /usr/local/bin/gosu.asc \
  && rm /usr/local/bin/gosu.asc \
  && chmod +x /usr/local/bin/gosu

ENV MONGO_RELEASE_FINGERPRINT 7F0CEB10
RUN gpg --keyserver pool.sks-keyservers.net --recv-keys $MONGO_RELEASE_FINGERPRINT

ENV MONGO_VERSION 3.0

RUN curl -SL "https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-amazon-3.0.0.tgz" -o mongo.tgz \
  && curl -SL "https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-amazon-3.0.0.tgz.sig" -o mongo.tgz.sig \
  && tar -xvf mongo.tgz -C /usr/local --strip-components=1 \
  && rm mongo.tgz*

COPY mongo-entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

# Expose ports.
#   - 27017: process
#   - 28017: http
EXPOSE 27017
EXPOSE 28017
CMD ["mongod", "-f", "/data/db/mongodb.conf"]
