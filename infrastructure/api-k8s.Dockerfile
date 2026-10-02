FROM ruby:4.0.6-slim

RUN apt-get update -qq && apt-get install --no-install-recommends -y build-essential libpq-dev git \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY apps/api/Gemfile apps/api/Gemfile.lock ./
RUN gem install bundler -v 4.0.19 --no-document && bundle install
COPY apps/api/ ./
RUN groupadd --gid 10001 app && useradd --uid 10001 --gid 10001 --create-home app \
    && mkdir -p /app/tmp /app/log && chown -R app:app /app
USER app
EXPOSE 3000
CMD ["bin/rails", "server", "-b", "0.0.0.0", "-P", "/tmp/hammerfall-puma.pid"]
