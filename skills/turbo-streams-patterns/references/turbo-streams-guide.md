# Targeted Turbo Streams — reference

The surgical update model: broadcast/render specific `<turbo-stream>` actions
against specific DOM ids. Complements `turbo-morphing` (the page-refresh model) —
reach here when you need precision: append a chat message, replace one card, toggle a
class, update an element outside the current frame. Grounded in the Piazza app
(`piazza-web/wip/analysis/02`, `07`).

## When targeted streams vs morphing

| Need | Use |
|---|---|
| High-fidelity append/prepend (chat), surgical element control | **targeted streams** (this skill) |
| Live multi-user "good enough" updates, simplest server | `broadcasts_refreshes` (see `turbo-morphing`) |
| Submit-and-redirect-back, many scattered changes | morph page refresh (see `turbo-morphing`) |

## Pattern 1 — model broadcasts over Action Cable

```ruby
class Message < ApplicationRecord
  belongs_to :conversation
  after_create -> {
    broadcast_append_later_to conversation,
      target: dom_id(conversation, :messages),
      partial: "messages/message"      # or locals:
  }
end
```
- `broadcast_append_later_to` (and `_replace_/_remove_/_prepend_`) enqueue a job →
  **needs an Active Job backend** (Sidekiq/SolidQueue). The non-`_later` variants
  broadcast inline.
- The view subscribes with `turbo_stream_from conversation, channel: "ConversationsChannel"`.

## Pattern 2 — authorize the stream (security boundary)

`turbo_stream_from` **signs** the stream name, but signing only proves the name wasn't
tampered with — **not** that this user may receive that record's broadcasts. A custom
channel must authorize before `stream_from`:

```ruby
class ConversationsChannel < ApplicationCable::Channel
  extend  Turbo::Streams::StreamName
  include Turbo::Streams::StreamName::ClassMethods

  def subscribed
    if conversation&.show?(organization)   # authorization
      stream_from stream_name
    else
      reject
    end
  end

  private
    def stream_name;   @stream_name   ||= verified_stream_name_from_params end
    def conversation;  @conversation  ||= GlobalID::Locator.locate(stream_name) end
end
```
**Footgun:** the default `Turbo::StreamsChannel` streams from any signed name with no
per-record check. If a record's broadcasts are private, use a custom channel that
calls `reject` when unauthorized. (Template: `authorized_channel.rb.tmpl`.)

## Pattern 3 — custom stream action (two halves that must match)

Add an action Turbo doesn't ship (e.g. `switch_class` — move a class from whoever has
it to a target). Both halves are required:

```js
// app/javascript/stream_actions/switch_class.js
import { StreamActions } from "@hotwired/turbo"
StreamActions.switch_class = function() {
  const className = this.getAttribute("class")
  document.querySelectorAll(`.${className}`).forEach(e => e.classList.remove(className))
  this.targetElements.forEach(e => e.classList.add(className))
}
```
```ruby
# app/helpers/turbo_stream_actions_helper.rb
module TurboStreamActionsHelper
  def switch_class(target, class_name)
    turbo_stream_action_tag(:switch_class, target: target, class: class_name)
  end
end
Turbo::Streams::TagBuilder.prepend(TurboStreamActionsHelper)
```
Then `turbo_stream.switch_class(dom_id(@conversation), "is-active")`. **A JS action
with no Ruby helper can't be emitted by the server; a Ruby helper with no JS action
sends a tag the client silently ignores.** Keep them paired (the linter checks this).

## Pattern 4 — stream tags *inside* a frame response

To patch an element **outside** the Turbo Frame you're responding into, embed
`turbo_stream.*` tags directly in the frame's HTML response (no separate
`*.turbo_stream.erb` template needed). Piazza uses this to update a badge/flash while
returning a frame. (See note 02.)

## Pattern 5 — Kredis presence to choose live vs notify

A Kredis set of online participants decides whether to rely on the live append or to
also create a notification / send email:

```ruby
kredis_set :online_participants, typed: :integer   # in the model

def notify_recipient(message)
  recipient_id = [seller_id, buyer_id].difference([message.from_id]).first
  notifications.create(message:, recipient_id:) unless online_participants.include?(recipient_id)
end
```
The channel maintains the set: `subscribed → add(org.id)`, `unsubscribed → remove(org.id)`.

## Sources

`piazza-web` `app/models/message.rb`, `app/channels/conversations_channel.rb`,
`app/javascript/stream_actions/switch_class.js`,
`app/helpers/turbo_stream_actions_helper.rb`, `app/models/conversation/notifier.rb`;
analysis notes 02 + 07.
