FROM ruby:4.0.6-slim

RUN apt-get update -qq && apt-get install --no-install-recommends -y build-essential libpq-dev git \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY apps/api/Gemfile apps/api/Gemfile.lock ./
RUN gem install bundler -v 4.0.19 --no-document && bundle install
ARG LOCAL_UID=1000
ARG LOCAL_GID=1000
RUN groupadd --gid ${LOCAL_GID} app && useradd --uid ${LOCAL_UID} --gid ${LOCAL_GID} --create-home app \
    && mkdir -p /app/tmp && chown -R app:app /app /usr/local/bundle
USER app
EXPOSE 3000
CMD ["bin/rails", "server", "-b", "0.0.0.0"]
