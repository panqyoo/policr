module Policr
  callbacker BlockRule do
    alias BlockRule = Model::BlockRule

    def handle(query, msg, data)
      chat_id = msg.chat.id
      msg_id = msg.message_id

      user_id = query.from.id

      action, id = data
      id = id.to_i

      rule = BlockRule.find id

      if rule == nil
        bot.answer_callback_query(query.id, text: t("blocked_content.rule.not_found"), show_alert: true)
        return
      end

      rule = rule.not_nil!
      is_global_rule = false

      has_permission =
        if rule.chat_id == bot.self_id # 全局规则
          is_global_rule = true
          user_id == bot.owner_id.to_i # 是否为管理员操作
        else                           # 私有规则
          role = Model::Toggle.trusted_admin?(rule.chat_id) ? :admin : :creator
          bot.has_permission?(rule.chat_id, query.from.id, role)
        end
      unless has_permission
        bot.answer_callback_query(query.id, text: "您没有权限操作此内容～")
        return
      end

      case action
      when "apply_to_message"
        def_toggle_apply message
      when "apply_to_nickname"
        def_toggle_apply nickname
      when "delete"
        BlockRule.delete id

        async_response

        bot.delete_message chat_id, msg_id
      when "enable"
        # 检测规则合法性
        begin
          RuleEngine.compile! rule.expression
        rescue e : Exception
          bot.answer_callback_query(query.id, text: "规则不合法，启用失败～", show_alert: true)
          return
        end
        BlockRule.enable! rule.id
        updated_text, updated_markup = updated_preview_settings rule.reload

        async_response

        bot.edit_message_text(
          chat_id,
          message_id: msg_id,
          text: updated_text,
          reply_markup: updated_markup
        )
      when "disable"
        BlockRule.disable rule.id
        updated_text, updated_markup = updated_preview_settings rule.reload

        async_response

        bot.edit_message_text(
          chat_id,
          message_id: msg_id,
          text: updated_text,
          reply_markup: updated_markup
        )
      else
        invalid_keyboard
        return
      end

      # 如果是全局规则更新则重新编译
      Cache.recompile_global_rules bot if is_global_rule
    end

    macro def_toggle_apply(target_s)
        selected = rule.in_{{target_s}}
        begin
          selected ? BlockRule.disapply_{{target_s}}(rule.id) : BlockRule.apply_{{target_s}}!(rule.id)

          updated_text, updated_markup = updated_preview_settings rule.reload

          async_response

          bot.edit_message_text(
            chat_id,
            message_id: msg_id,
            text: updated_text,
            reply_markup: updated_markup
          )
        rescue e : Exception
          bot.answer_callback_query(query.id, text: e.to_s, show_alert: true)
        end
    end

    def updated_preview_settings(block_content)
      midcall StartCommander do
        {
          _commander.create_block_rule_text(block_content),
          _commander.create_block_rule_markup(block_content),
        }
      end || {nil, nil}
    end
  end
end
