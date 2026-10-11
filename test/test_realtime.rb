# frozen_string_literal: true

require_relative "test_helper"

class TestRealtime < PocketBaseIntegrationTest
  def test_subscribe_receives_create_event
    queue = Queue.new
    unsub = pb.collection("posts").subscribe("*") { |e| queue << e }
    assert pb.realtime.connected?
    refute_empty pb.realtime.client_id

    title = unique_title("rt")
    rec = pb.collection("posts").create("title" => title)

    event = Timeout.timeout(10) { queue.pop }
    assert_equal "create", event["action"]
    assert_equal rec["id"], event["record"]["id"]
    assert_equal title, event["record"]["title"]

    unsub.call
    refute pb.realtime.connected?
  ensure
    pb.collection("posts").delete(rec["id"]) if rec
    pb.realtime.disconnect
  end

  def test_subscribe_specific_record
    rec = pb.collection("posts").create("title" => unique_title("rtsingle"))
    queue = Queue.new
    unsub = pb.collection("posts").subscribe(rec["id"]) { |e| queue << e }

    pb.collection("posts").update(rec["id"], "views" => 99)

    event = Timeout.timeout(10) { queue.pop }
    assert_equal "update", event["action"]
    assert_equal 99, event["record"]["views"]

    unsub.call
  ensure
    pb.collection("posts").delete(rec["id"]) if rec
    pb.realtime.disconnect
  end

  def test_unsubscribe_by_topic
    queue = Queue.new
    pb.collection("posts").subscribe("*") { |e| queue << e }
    assert pb.realtime.connected?

    pb.collection("posts").unsubscribe("*")
    refute pb.realtime.connected?
  ensure
    pb.realtime.disconnect
  end
end
