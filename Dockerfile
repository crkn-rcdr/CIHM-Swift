FROM perl:5.30

RUN groupadd cihm && useradd -g cihm -m cihm && \
  cpanm -n Carton && mkdir -p /opt/swift && \
  chown cihm.cihm /opt/swift

WORKDIR /opt/swift

USER cihm

COPY cpanfile* /opt/swift/

RUN carton install --deployment || (cat /home/cihm/.cpanm/work/*/build.log && exit 1)

COPY bin /opt/swift/bin
COPY lib /opt/swift/lib
COPY t /opt/swift/t
