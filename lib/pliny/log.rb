module Pliny
  module Log
    def log(data, &block)
      log_to_stream(stdout || $stdout, merge_log_contexts(data), &block)
    end

    def log_exception(e, data = {})
      exception_id = e.object_id

      # Log backtrace in reverse order for easier digestion.
      if e.backtrace
        e.backtrace.reverse.each do |backtrace|
          log_to_stream(stderr || $stderr, merge_log_contexts(
            exception_id: exception_id,
            backtrace:    backtrace
          ))
        end
      end

      # then log the exception message last so that it's as close to the end of
      # a log trace as possible
      data.merge!(
        exception:    true,
        class:        e.class.name,
        message:      e.message,
        exception_id: exception_id
      )

      data[:status] = e.status if e.respond_to?(:status)

      log_to_stream(stderr || $stderr, merge_log_contexts(data))
    end

    def context(data, &block)
      old = local_context
      self.local_context = old.merge(data)
      res = block.call
    ensure
      self.local_context = old
      res
    end

    def default_context=(default_context)
      @default_context = default_context
    end

    def default_context
      @default_context || {}
    end

    def stdout=(stream)
      @stdout = stream
    end

    def stdout
      @stdout
    end

    def stderr=(stream)
      @stderr = stream
    end

    def stderr
      @stderr
    end

    private

    def merge_log_contexts(data)
      default_context.merge(log_context.merge(local_context.merge(data)))
    end

    def local_context
      RequestStore.store[:local_context] ||= {}
    end

    def local_context=(h)
      RequestStore.store[:local_context] = h
    end

    def log_context
      RequestStore.store[:log_context] || {}
    end

    def log_to_stream(stream, data, &block)
      unless block
        str = unparse(data)
        stream.print(str + "\n")
      else
        data = data.dup
        start = Time.now
        log_to_stream(stream, data.merge(at: "start"))
        begin
          res = yield
          log_to_stream(stream, data.merge(
            at: "finish", elapsed: (Time.now - start).to_f))
          res
        rescue
          log_to_stream(stream, data.merge(
            at: "exception", elapsed: (Time.now - start).to_f))
          raise $!
        end
      end
    end

    def quote_string(k, v)
      # try to find a quote style that fits
      if !v.include?('"')
        %{#{k}="#{v}"}
      elsif !v.include?("'")
        %{#{k}='#{v}'}
      else
        %{#{k}="#{v.gsub(/"/, '\\"')}"}
      end
    end

    def unparse(attrs)
      attrs.map { |k, v| unparse_pair(k, v) }.compact.join(" ")
    end

    def unparse_pair(k, v)
      v = v.call if v.is_a?(Proc)
      # only quote strings if they include whitespace
      if v == nil
        nil
      elsif v == true
        k
      elsif v.is_a?(Float)
        "#{k}=#{format("%.3f", v)}"
      elsif v.is_a?(String) && v =~ /\s/
        quote_string(k, v)
      elsif v.is_a?(Time)
        "#{k}=#{v.iso8601}"
      else
        "#{k}=#{v}"
      end
    end
  end
end
