FROM chrislusf/seaweedfs:4.22
RUN apk add --no-cache aws-cli
COPY docker/s3.json /etc/seaweedfs/s3.json
COPY docker/entrypoint.sh /dsp-object-storage-entrypoint.sh
RUN chmod +x /dsp-object-storage-entrypoint.sh
ENTRYPOINT ["/dsp-object-storage-entrypoint.sh"]
