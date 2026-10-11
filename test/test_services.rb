# frozen_string_literal: true

require_relative "test_helper"

class TestServices < PocketBaseIntegrationTest
  def test_settings_get_and_update
    # NB: PocketBase replaces nested settings structs wholesale, so updates
    # must round-trip the full settings object.
    settings = pb.settings.get_all
    assert settings.key?("meta")

    original = settings["meta"]["appName"]
    settings["meta"]["appName"] = "TestApp"
    pb.settings.update(settings)
    assert_equal "TestApp", pb.settings.get_all["meta"]["appName"]
  ensure
    if defined?(original)
      s = pb.settings.get_all
      s["meta"]["appName"] = original
      pb.settings.update(s)
    end
  end

  def test_backups_lifecycle
    assert_equal true, pb.backups.create("test-backup.zip")
    list = pb.backups.get_full_list
    key = list.map { |b| b["key"] }.find { |k| k.include?("test-backup") }
    refute_nil key

    token = pb.files.get_token
    url = pb.backups.get_download_url(token, key)
    assert_match(%r{/api/backups/.+\?token=.+}, url)

    assert_equal true, pb.backups.delete(key)
    list2 = pb.backups.get_full_list
    assert_nil list2.map { |b| b["key"] }.find { |k| k.include?("test-backup") }
  end

  def test_logs_list_get_stats_and_truncate
    assert_equal true, pb.logs.truncate
    pb.collection("posts").create("title" => unique_title("log"))

    # request logs are written asynchronously; poll briefly
    list = nil
    20.times do
      list = pb.logs.get_list(1, 5)
      break if list["totalItems"] >= 1

      sleep 0.25
    end
    assert_operator list["totalItems"], :>=, 1
    first = list["items"][0]
    one = pb.logs.get_one(first["id"])
    assert_equal first["id"], one["id"]

    stats = pb.logs.get_stats
    assert_kind_of Array, stats

    err = assert_raises(PocketBase::ClientResponseError) { pb.logs.get_one("") }
    assert_equal 404, err.status
  end

  def test_crons_list
    jobs = pb.crons.get_full_list
    assert_kind_of Array, jobs
  end

  def test_crons_run_missing_raises
    err = assert_raises(PocketBase::ClientResponseError) { pb.crons.run("no-such-job") }
    assert_equal 404, err.status
  end

  def test_sql_run
    result = pb.sql.run("SELECT 1 AS one")
    assert_equal 1, result["rows"].length
    assert_equal "1", result["rows"][0][0]
    assert_includes result["columns"].map { |c| c["name"] }, "one"
  end

  def test_collections_meta_endpoints
    scaffolds = pb.collections.get_scaffolds
    assert scaffolds.key?("base")
    assert scaffolds.key?("auth")

    providers = pb.collections.get_all_oauth2_providers
    assert_kind_of Array, providers

    result = pb.collections.dry_run_view_query("SELECT id FROM posts")
    assert_kind_of Hash, result
    assert_kind_of Array, result["sample"]
  end

  def test_collections_truncate
    rec = pb.collection("posts").create("title" => unique_title("trunc"))
    assert_equal true, pb.collections.truncate("posts")
    assert_raises(PocketBase::ClientResponseError) { pb.collection("posts").get_one(rec["id"]) }
  end

  def test_collections_crud
    base = pb.collections.get_scaffolds["base"].dup
    base.delete("id") # scaffolds carry an id; creating with it collides
    base["name"] = "tmpcol_#{SecureRandom.hex(3)}"
    col = pb.collections.create(base)
    assert_equal base["name"], col["name"]

    fetched = pb.collections.get_one(col["id"])
    assert_equal col["id"], fetched["id"]

    updated = pb.collections.update(col["id"], "listRule" => "")
    assert_equal "", updated["listRule"]

    assert_equal true, pb.collections.delete(col["id"])
  end
end
