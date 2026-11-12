FROM redmine:7.0.3 AS theme
ADD --checksum=sha256:3f1ad884607b8338f9de742b7ef290d126bbebce6d52ed8e9db78eb2ecba209c https://github.com/techolve/redmine-shadcn-theme/releases/download/v0.2.3/redmine-shadcn-theme-v0.2.3.zip /tmp/shadcn.zip
RUN ruby -rzip -e 'Zip::File.open("/tmp/shadcn.zip") { |archive| archive.each { |entry| entry.extract(entry.name, destination_directory: "/tmp/theme") } }'

FROM redmine:7.0.3
COPY --from=theme /tmp/theme/shadcn themes/shadcn
COPY plugins/redmine_portfolio plugins/redmine_portfolio
COPY docker/configuration.yml config/configuration.yml
COPY scripts/bootstrap.rb scripts/bootstrap.rb
CMD ["bundle", "exec", "sh", "-ec", "rails runner scripts/bootstrap.rb && exec rails server -b 0.0.0.0"]
