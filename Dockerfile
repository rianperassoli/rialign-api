# syntax=docker/dockerfile:1
ARG RUBY_VERSION=3.3.0
FROM ruby:$RUBY_VERSION-slim AS base

WORKDIR /app

# Packages needed at runtime (libpq for pg) and build time.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential libpq-dev postgresql-client git curl && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV=development \
    BUNDLE_PATH=/usr/local/bundle

# Install gems first for better layer caching.
COPY Gemfile Gemfile.lock* ./
RUN bundle install

COPY . .

EXPOSE 3000

ENTRYPOINT ["./bin/docker-entrypoint"]
CMD ["bin/rails", "server", "-b", "0.0.0.0"]
