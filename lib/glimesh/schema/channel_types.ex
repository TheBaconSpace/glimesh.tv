defmodule Glimesh.Schema.ChannelTypes do
  @moduledoc false
  use Absinthe.Schema.Notation

  import Absinthe.Resolution.Helpers

  alias Glimesh.Repo
  alias Glimesh.Resolvers.StreamsResolver
  alias Glimesh.Streams

  object :streams_queries do
    @desc "List all channels"
    field :channels, list_of(:channel) do
      resolve(&StreamsResolver.all_channels/2)
    end

    @desc "Query individual channel"
    field :channel, :channel do
      arg(:id, :id)
      arg(:username, :string)
      arg(:stream_key, :string)
      resolve(&StreamsResolver.find_channel/2)
    end

    @desc "List all categories"
    field :categories, list_of(:category) do
      resolve(&StreamsResolver.all_categories/2)
    end

    @desc "Query individual category"
    field :category, :category do
      arg(:slug, :string)
      resolve(&StreamsResolver.find_category/2)
    end

    @desc "List all subscribers or subscribees"
    field :subscriptions, list_of(:sub) do
      arg(:streamer_username, :string)
      arg(:user_username, :string)
      resolve(&StreamsResolver.all_subscriptions/2)
    end

    @desc "List all follows or followers"
    field :followers, list_of(:follower) do
      arg(:streamer_username, :string)
      arg(:user_username, :string)
      resolve(&StreamsResolver.all_followers/2)
    end
  end

  object :streams_mutations do
    @desc "Start a stream"
    field :start_stream, type: :stream do
      arg(:channel_id, non_null(:id))

      resolve(&StreamsResolver.start_stream/3)
    end

    @desc "End a stream"
    field :end_stream, type: :stream do
      arg(:channel_id, non_null(:id))

      resolve(&StreamsResolver.end_stream/3)
    end

    @desc "Update a stream's metadata"
    field :log_stream_metadata, type: :stream do
      arg(:channel_id, non_null(:id))
      arg(:metadata, non_null(:stream_metadata_input))

      resolve(&StreamsResolver.log_stream_metadata/3)
    end

    # @desc "Create a stream"
    # field :create_stream, type: :stream do
    #   arg(:channel_id, non_null(:id))

    #   resolve(&StreamsResolver.create_stream/3)
    # end

    # @desc "Update a stream"
    # field :update_stream, type: :stream do
    #   arg(:id, non_null(:id))

    #   resolve(&StreamsResolver.update_stream/3)
    # end
  end

  object :streams_subscriptions do
    field :channel, :channel do
      arg(:id, :id)

      config(fn args, _ ->
        case Map.get(args, :id) do
          nil -> {:ok, topic: [Streams.get_subscribe_topic(:channel)]}
          channel_id -> {:ok, topic: [Streams.get_subscribe_topic(:channel, channel_id)]}
        end
      end)
    end

    field :chat_message, :chat_message do
      arg(:channel_id, :id)

      config(fn args, _ ->
        case Map.get(args, :channel_id) do
          nil -> {:ok, topic: [Streams.get_subscribe_topic(:chat)]}
          channel_id -> {:ok, topic: [Streams.get_subscribe_topic(:chat, channel_id)]}
        end
      end)
    end
  end

  enum :channel_status do
    value(:live, as: "live")
    value(:offline, as: "offline")
  end

  @desc "Categories are the containers for live streaming content."
  object :category do
    field :id, :id
    field :name, :string, description: "Name of the category"
    field :tag_name, :string, description: "Parent Name and Name of the category in one string"
    field :slug, :string, description: "Slug of the category"

    field :parent, :category,
      resolve: dataloader(Repo),
      description: "Parent category, if null this is a parent category"
  end

  @desc "A channel is a user's actual container for live streaming."
  object :channel do
    field :id, :id

    field :status, :channel_status
    field :title, :string, description: "The title of the current stream, live or offline."
    field :category, :category, resolve: dataloader(Repo)
    field :language, :string, description: "The language a user can expect in the stream."
    field :thumbnail, :string

    field :stream_key, :string do
      resolve(fn channel, _, %{context: %{current_user: current_user}} ->
        if current_user.is_admin do
          {:ok, channel.stream_key}
        else
          {:error, "Unauthorized to access streamKey field."}
        end
      end)
    end

    field :inaccessible, :boolean

    field :chat_rules_md, :string
    field :chat_rules_html, :string

    field :stream, :stream, resolve: dataloader(Repo)

    field :streamer, non_null(:user), resolve: dataloader(Repo)
    field :chat_messages, list_of(:chat_message), resolve: dataloader(Repo)

    field :user, non_null(:user),
      resolve: dataloader(Repo),
      deprecate: "Please use the streamer field"

    field :inserted_at, non_null(:naive_datetime)
    field :updated_at, non_null(:naive_datetime)
  end

  @desc "A stream is a single live stream in, either current or historical."
  object :stream do
    field :id, :id

    field :channel, non_null(:channel), resolve: dataloader(Repo)

    field :title, :string, description: "The title of the stream."
    field :category, non_null(:category), resolve: dataloader(Repo)
    field :metadata, list_of(:stream_metadata), resolve: dataloader(Repo)

    field :started_at, non_null(:naive_datetime)
    field :ended_at, :naive_datetime

    # field :viewers, :viewers, resolve: dataloader(Repo)
    # field :chatters, :chatters, resolve: dataloader(Repo)

    field :count_viewers, :integer
    field :count_chatters, :integer

    field :peak_viewers, :integer
    field :peak_chatters, :integer
    field :avg_viewers, :integer
    field :avg_chatters, :integer
    field :new_subscribers, :integer
    field :resub_subscribers, :integer

    field :inserted_at, non_null(:naive_datetime)
    field :updated_at, non_null(:naive_datetime)
  end

  @desc "A single instance of stream metadata."
  object :stream_metadata do
    field :id, :id

    field :stream, non_null(:stream), resolve: dataloader(Repo)

    field :ingest_server, :string
    field :ingest_viewers, :string
    field :stream_time_seconds, :integer

    field :source_bitrate, :integer
    field :source_ping, :integer

    field :recv_packets, :integer
    field :lost_packets, :integer
    field :nack_packets, :integer

    field :vendor_name, :string
    field :vendor_version, :string

    field :video_codec, :string
    field :video_height, :integer
    field :video_width, :integer
    field :audio_codec, :string

    field :inserted_at, non_null(:naive_datetime)
    field :updated_at, non_null(:naive_datetime)
  end

  @desc "A chat message sent to a channel by a user."
  object :chat_message do
    field :id, :id
    field :message, :string, description: "The chat message."

    field :channel, non_null(:channel), resolve: dataloader(Repo)
    field :user, non_null(:user), resolve: dataloader(Repo)

    field :inserted_at, non_null(:naive_datetime)
    field :updated_at, non_null(:naive_datetime)
  end

  @desc "A follower is a user who subscribes to notifications for a particular channel."
  object :follower do
    field :id, :id
    field :has_live_notifications, :boolean

    field :streamer, non_null(:user), resolve: dataloader(Repo)
    field :user, non_null(:user), resolve: dataloader(Repo)

    field :inserted_at, non_null(:naive_datetime)
    field :updated_at, non_null(:naive_datetime)
  end

  @desc "A subscription is an exchange of money for support."
  object :sub do
    field :id, :id
    field :is_active, :boolean
    field :started_at, non_null(:datetime)
    field :ended_at, :datetime
    field :price, :integer
    field :product_name, :string

    field :streamer, non_null(:user), resolve: dataloader(Repo)
    field :user, non_null(:user), resolve: dataloader(Repo)

    field :inserted_at, non_null(:naive_datetime)
    field :updated_at, non_null(:naive_datetime)
  end
end
