defmodule Glimesh.StreamsTest do
  use Glimesh.DataCase
  use Bamboo.Test

  import Glimesh.AccountsFixtures
  alias Glimesh.Chat
  alias Glimesh.Streams

  describe "timeout_user/3" do
    setup do
      %{
        channel: channel_fixture(),
        moderator: user_fixture(),
        user: user_fixture()
      }
    end

    test "times out a user and removes messages successfully", %{
      channel: channel,
      moderator: moderator,
      user: user
    } do
      {:ok, _} = Chat.create_chat_message(channel, user, %{message: "bad message"})
      {:ok, _} = Chat.create_chat_message(channel, moderator, %{message: "good message"})
      assert length(Chat.list_chat_messages(channel)) == 2

      {:ok, _} = Glimesh.Streams.add_moderator(channel, moderator)

      {:ok, _} = Streams.timeout_user(channel, moderator, user)
      assert length(Chat.list_chat_messages(channel)) == 1
    end

    test "adds log of timeout action", %{channel: channel, moderator: moderator, user: user} do
      {:ok, _} = Glimesh.Streams.add_moderator(channel, moderator)
      {:ok, record} = Streams.timeout_user(channel, moderator, user)

      assert record.channel.id == channel.id
      assert record.moderator.id == moderator.id
      assert record.user.id == user.id
      assert record.action == "timeout"
    end

    test "moderation privileges are required to timeout", %{
      channel: channel,
      moderator: moderator,
      user: user
    } do
      assert_raise RuntimeError,
                   "User does not have permission to moderate.",
                   fn -> Streams.timeout_user(channel, moderator, user) end
    end
  end

  describe "followers" do
    @valid_attrs %{has_live_notifications: true}
    @update_attrs %{has_live_notifications: false}
    @invalid_attrs %{has_live_notifications: nil}

    def followers_fixture do
      streamer = streamer_fixture()
      user = user_fixture()

      {:ok, followers} = Streams.follow(streamer, user)

      followers
    end

    test "follow/2 successfully follows streamer" do
      streamer = streamer_fixture()
      user = user_fixture()
      Streams.follow(streamer, user)

      followed = Streams.list_followed_channels(user)

      assert Enum.map(followed, fn x -> x.user.username end) == [streamer.username]
    end

    test "unfollow/2 successfully unfollows streamer" do
      streamer = streamer_fixture()
      user = user_fixture()
      Streams.follow(streamer, user)
      followed = Streams.list_followed_channels(user)

      assert Enum.map(followed, fn x -> x.user.username end) == [streamer.username]

      Streams.unfollow(streamer, user)
      assert Streams.list_followed_channels(user) == []
    end

    test "is_following?/1 detects active follow" do
      streamer = streamer_fixture()
      user = user_fixture()
      Streams.follow(streamer, user)
      assert Streams.is_following?(streamer, user) == true
    end

    test "follow/2 twice returns error changeset" do
      streamer = streamer_fixture()
      user = user_fixture()

      Streams.follow(streamer, user)
      assert {:error, %Ecto.Changeset{}} = Streams.follow(streamer, user)
    end
  end

  describe "categories" do
    alias Glimesh.Streams.Category

    @valid_attrs %{
      name: "some name"
    }
    @update_attrs %{
      name: "some updated name"
    }
    @invalid_attrs %{name: nil}

    def category_fixture(attrs \\ %{}) do
      {:ok, category} =
        attrs
        |> Enum.into(@valid_attrs)
        |> Streams.create_category()

      category
    end

    test "list_categories/0 returns all categories" do
      category = category_fixture()
      assert Enum.member?(Enum.map(Streams.list_categories(), fn x -> x.name end), category.name)
    end

    test "get_category_by_id!/1 returns the category with given id" do
      category = category_fixture()
      assert Streams.get_category_by_id!(category.id) == category
    end

    test "create_category/1 with valid data creates a category" do
      assert {:ok, %Category{} = category} = Streams.create_category(@valid_attrs)
      assert category.name == "some name"
      assert category.slug == "some-name"
    end

    test "create_category/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Streams.create_category(@invalid_attrs)
    end

    test "update_category/2 with valid data updates the category" do
      category = category_fixture()
      assert {:ok, %Category{} = category} = Streams.update_category(category, @update_attrs)
      assert category.name == "some updated name"
      assert category.slug == "some-updated-name"
    end

    test "update_category/2 with invalid data returns error changeset" do
      category = category_fixture()
      assert {:error, %Ecto.Changeset{}} = Streams.update_category(category, @invalid_attrs)
      assert category == Streams.get_category_by_id!(category.id)
    end

    test "delete_category/1 deletes the category" do
      category = category_fixture()
      assert {:ok, %Category{}} = Streams.delete_category(category)
      assert_raise Ecto.NoResultsError, fn -> Streams.get_category_by_id!(category.id) end
    end

    test "change_category/1 returns a category changeset" do
      category = category_fixture()
      assert %Ecto.Changeset{} = Streams.change_category(category)
    end
  end

  describe "ingest stream api" do
    setup do
      {:ok, channel: channel_fixture()}
    end

    test "start_stream/1 successfully starts a stream", %{channel: channel} do
      {:ok, stream} = Streams.start_stream(channel)
      new_channel = Streams.get_channel!(channel.id)

      assert stream.started_at != nil
      assert stream.ended_at == nil
      assert stream.id == new_channel.stream_id
      assert stream.category_id == new_channel.category_id
      assert new_channel.status == "live"
    end

    test "end_stream/1 successfully stops a stream", %{channel: channel} do
      {:ok, _} = Streams.start_stream(channel)
      fresh_channel = Streams.get_channel!(channel.id)
      {:ok, stream} = Streams.end_stream(fresh_channel)
      new_channel = Streams.get_channel!(channel.id)

      assert stream.started_at != nil
      assert stream.ended_at != nil
      assert new_channel.status == "offline"
      assert new_channel.stream_id == nil
    end

    test "log_stream_metadata/1 successfully logs some metadata", %{channel: channel} do
      {:ok, _} = Streams.start_stream(channel)

      incoming_attrs = %{
        audio_codec: "mp3",
        ingest_server: "test",
        ingest_viewers: 32,
        stream_time_seconds: 1024,
        lost_packets: 0,
        nack_packets: 0,
        recv_packets: 100,
        source_bitrate: 5000,
        source_ping: 100,
        vendor_name: "OBS",
        vendor_version: "1.0.0",
        video_codec: "mp4",
        video_height: 1024,
        video_width: 768
      }

      fresh_channel = Streams.get_channel!(channel.id)
      {:ok, stream} = Streams.log_stream_metadata(fresh_channel, incoming_attrs)

      assert incoming_attrs = hd(stream.metadata)
    end
  end
end
