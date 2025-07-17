FROM perl:5-bookworm

RUN mkdir -p /usr/src/app && groupadd --gid 1000 postgres && useradd -ms /bin/bash -u 1000 -g 1000 postgres && chown -R postgres:postgres /usr/src/app
WORKDIR /usr/src/app

ENV DEBIAN_FRONTEND=noninteractive 

RUN --mount=target=/var/lib/apt/lists,type=cache --mount=type=cache,target=/var/cache/apt apt-get update && apt-get install --no-install-recommends -y postgresql-common r-base r-recommended pandoc poppler-utils tini && \
  /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y && apt-get install --no-install-recommends -y postgresql postgresql-17-pgvector

COPY --chown=postgres:postgres cpanfile /usr/src/app

RUN --mount=type=cache,target=/root/.cpanm cpanm -v -f --installdeps --notest . -M https://cpan.metacpan.org

RUN ln -s /usr/bin/R /usr/local/bin/R && \
    R -e "install.packages(c('rjson'), dependencies=TRUE, repos='http://cran.rstudio.com/')" && \
    echo "local all  all  trust" > /etc/postgresql/17/main/pg_hba.conf && \
    echo "host  all  all  127.0.0.1/32 trust" >> /etc/postgresql/17/main/pg_hba.conf && \
    echo "host  all  all  ::1/128    trust" >> /etc/postgresql/17/main/pg_hba.conf && \
    echo "listen_addresses='*'" >> /etc/postgresql/17/main/postgresql.conf && \
    chown -R postgres:postgres /var/run/postgresql

USER postgres

COPY --chown=postgres:postgres sql_template.sql .
COPY --chown=postgres:postgres entrypoint.sh .
COPY --chown=postgres:postgres Application .

# RUN curl -fsSL https://ollama.com/install.sh | sh
# COPY install_ollama.sh /app
# RUN /app/install_ollama.sh

EXPOSE 8888

# cleanly shutdown postgres by using process group killing
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/usr/src/app/entrypoint.sh"]
