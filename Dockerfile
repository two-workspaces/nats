# Upstream's official NATS server image (Alpine variant, so a shell entrypoint can write
# the config), pinned. busybox-extras adds httpd for the notice page when the server
# can't start.
FROM nats:2.15.3-alpine

RUN apk add --no-cache busybox-extras

COPY --chmod=0755 railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
