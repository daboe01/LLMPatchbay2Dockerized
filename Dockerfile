# Use a base image that includes Perl
FROM perl:5-bookworm

# Create a non-root user and application directory
RUN mkdir -p /usr/src/app && \
    groupadd --gid 1000 postgres && \
    useradd -ms /bin/bash -u 1000 -g 1000 postgres && \
    chown -R postgres:postgres /usr/src/app

WORKDIR /usr/src/app

# Set non-interactive frontend for package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies for Perl, PostgreSQL, R, and Python
RUN --mount=target=/var/lib/apt/lists,type=cache --mount=type=cache,target=/var/cache/apt \
    apt-get update && \
    apt-get install --no-install-recommends -y \
    postgresql-common \
    r-base \
    r-recommended \
    pandoc \
    poppler-utils \
    tini \
    jq \
    python3 \
    python3-pip \
    python3-venv && \
    # Add the official PostgreSQL repository
    /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y && \
    # Install PostgreSQL 17 and its pgvector extension explicitly
    apt-get install --no-install-recommends -y \
    postgresql-17 \
    postgresql-17-pgvector

# Copy Perl dependencies file
COPY --chown=postgres:postgres cpanfile /usr/src/app

# Install Perl dependencies
RUN --mount=type=cache,target=/root/.cpanm cpanm -v -f --installdeps --notest . -M https://cpan.metacpan.org

# Configure R and PostgreSQL
RUN ln -s /usr/bin/R /usr/local/bin/R && \
    R -e "install.packages(c('rjson'), dependencies=TRUE, repos='http://cran.rstudio.com/')" && \
    echo "local all  all  trust" > /etc/postgresql/17/main/pg_hba.conf && \
    echo "host  all  all  127.0.0.1/32 trust" >> /etc/postgresql/17/main/pg_hba.conf && \
    echo "host  all  all  ::1/128    trust" >> /etc/postgresql/17/main/pg_hba.conf && \
    echo "listen_addresses='*'" >> /etc/postgresql/17/main/postgresql.conf && \
    chown -R postgres:postgres /var/run/postgresql

# --- Python Setup ---
# Create and set up the Python virtual environment for langextract
RUN python3 -m venv /opt/langextract_env
ENV PATH="/opt/langextract_env/bin:$PATH"

# Copy langextract related files
COPY --chown=postgres:postgres langextract-tgi /usr/src/app/langextract-tgi
COPY --chown=postgres:postgres lang_extract.py /usr/src/app/lang_extract.py

# Install Python dependencies within the virtual environment
RUN . /opt/langextract_env/bin/activate && \
    pip install langextract && \
    cd /usr/src/app/langextract-tgi && pip install -e .

# --- End Python Setup ---

# Switch to the non-root user
USER postgres

# Copy application files
COPY --chown=postgres:postgres sql_template.sql .
COPY --chown=postgres:postgres entrypoint.sh .
COPY --chown=postgres:postgres Application .

# Expose the application port
EXPOSE 8888

# Set the entrypoint to cleanly shutdown postgres
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/usr/src/app/entrypoint.sh"]
