module Spyke
  class Result
    attr_reader :body

    def self.new_from_response(response)
      new(response.body)
    end

    def initialize(body)
      @body = HashWithIndifferentAccess.new(body)
    end

    def data
      e = body[:data]
      e.blank? ? {} : e
    end

    def metadata
      body[:metadata] || {}
    end

    def errors
      e = body[:errors]
      e.blank? ? {} : e
    end
  end
end
