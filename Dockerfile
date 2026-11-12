FROM redmine:7.0.3 AS theme
ADD --checksum=sha256:3f1ad884607b8338f9de742b7ef290d126bbebce6d52ed8e9db78eb2ecba209c https://github.com/techolve/redmine-shadcn-theme/releases/download/v0.2.3/redmine-shadcn-theme-v0.2.3.zip /tmp/shadcn.zip
RUN ruby -rzip -e 'Zip::File.open("/tmp/shadcn.zip") { |archive| archive.each { |entry| entry.extract(entry.name, destination_directory: "/tmp/theme") } }'

ADD --checksum=sha256:5e43d5cdd30cabe790e7702c9add093c8448bfe87862dc32490daf3dd76552c9 https://github.com/gagnieray/opale/releases/download/1.7.2/opale-1.7.2.zip /tmp/opale.zip
RUN ruby -rzip -e 'Zip::File.open("/tmp/opale.zip") { |archive| archive.each { |entry| entry.extract(entry.name, destination_directory: "/tmp/theme") } }'

FROM redmine:7.0.3
COPY --from=theme /tmp/theme/shadcn themes/shadcn
COPY --from=theme /tmp/theme/opale-1.7.2 themes/opale
COPY plugins/redmine_portfolio plugins/redmine_portfolio
COPY docker/configuration.yml config/configuration.yml
COPY scripts/bootstrap.rb scripts/bootstrap.rb
CMD ["bundle", "exec", "sh", "-ec", "rails runner scripts/bootstrap.rb && exec rails server -b 0.0.0.0"]
