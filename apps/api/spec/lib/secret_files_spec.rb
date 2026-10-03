require "spec_helper"
require "tmpdir"
require_relative "../../lib/secret_files"

RSpec.describe SecretFiles do
  it "preserves ordinary environment configuration" do
    env = { "DATABASE_URL" => "postgresql://local/db" }
    described_class.load!(env: env)
    expect(env["DATABASE_URL"]).to eq("postgresql://local/db")
  end

  it "loads mounted values, stripping only one terminal newline" do
    Dir.mktmpdir do |dir|
      db = File.join(dir, "database-url")
      key = File.join(dir, "secret-key-base")
      File.write(db, "postgresql://local/db\n")
      File.write(key, "private-key \n")
      env = { "DATABASE_URL_FILE" => db, "SECRET_KEY_BASE_FILE" => key }
      described_class.load!(env: env)
      expect(env).to include("DATABASE_URL" => "postgresql://local/db", "SECRET_KEY_BASE" => "private-key ")
    end
  end

  it "fails clearly on missing files and conflicting sources without exposing values" do
    expect { described_class.load!(env: { "DATABASE_URL_FILE" => "/missing/private-value" }) }
      .to raise_error(ArgumentError, /DATABASE_URL_FILE must name a readable file/)
    expect { described_class.load!(env: { "DATABASE_URL_FILE" => "/missing", "DATABASE_URL" => "private-value" }) }
      .to raise_error(ArgumentError, /DATABASE_URL_FILE conflicts with DATABASE_URL/)
  end

  it "requires a verified Cloud SQL hostname and CA" do
    Dir.mktmpdir do |dir|
      ca = File.join(dir, "ca.pem")
      File.write(ca, "public CA")
      valid = "postgresql://user:private@instance.europe-west4.sql-psa.goog:5432/hammerfall?sslmode=verify-full&sslrootcert=#{ca}"
      expect { described_class.load!(env: { "DATABASE_CONNECTION_MODE" => "cloud_sql", "DATABASE_URL" => valid }) }
        .not_to raise_error
      [ valid.sub("verify-full", "require"), valid.sub("sql-psa.goog", "example.net"),
        valid.sub(ca, "/missing/ca.pem"), "#{valid}&sslmode=require" ].each do |invalid|
        expect { described_class.load!(env: { "DATABASE_CONNECTION_MODE" => "cloud_sql", "DATABASE_URL" => invalid }) }
          .to raise_error(ArgumentError, /cloud_sql requires/)
      end
    end
  end
end
