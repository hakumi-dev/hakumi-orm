# typed: strict
# frozen_string_literal: true

module HakumiORM
  class SqlLogFormatter
    extend T::Sig

    KEYWORDS = T.let(
      %w[
        SELECT FROM WHERE JOIN LEFT RIGHT INNER OUTER ON GROUP BY HAVING ORDER LIMIT OFFSET
        INSERT INTO VALUES UPDATE SET DELETE RETURNING DISTINCT AS AND OR NOT NULL IS IN EXISTS
        COUNT SUM AVG MIN MAX BEGIN COMMIT ROLLBACK SAVEPOINT RELEASE
      ].freeze,
      T::Array[String]
    )
    KEYWORD_REGEX = T.let(/\b(?:#{Regexp.union(KEYWORDS).source})\b/i, Regexp)

    RESET = T.let("\e[0m", String)
    BOLD = T.let("\e[1m", String)
    DIM = T.let("\e[2m", String)
    CYAN = T.let("\e[36m", String)
    YELLOW = T.let("\e[33m", String)
    MAGENTA = T.let("\e[35m", String)

    sig do
      params(
        elapsed_ms: Float,
        sql: String,
        params: T::Array[PGValue],
        note: T.nilable(String),
        colorize: T::Boolean
      ).returns(String)
    end
    def self.format(elapsed_ms:, sql:, params:, note:, colorize:)
      header = "HakumiORM SQL"
      timing = "(#{elapsed_ms}ms)"
      formatted_sql = highlight_sql(sql, colorize: colorize)
      suffix =
        if note
          rendered_note = colorize ? color(note, MAGENTA) : note
          " [#{rendered_note}]"
        else
          ""
        end

      if params.empty?
        "#{colorize ? color(header, CYAN, bold: true) : header} #{colorize ? color(timing, YELLOW) : timing} #{formatted_sql}#{suffix}"
      else
        binds = params.inspect
        rendered_header = colorize ? color(header, CYAN, bold: true) : header
        rendered_timing = colorize ? color(timing, YELLOW) : timing
        rendered_binds = colorize ? color(binds, DIM) : binds
        "#{rendered_header} #{rendered_timing} #{formatted_sql}#{suffix} #{rendered_binds}"
      end
    end

    sig { params(sql: String, colorize: T::Boolean).returns(String) }
    def self.highlight_sql(sql, colorize:)
      return sql unless colorize

      sql.gsub(KEYWORD_REGEX) { |word| color(word.upcase, BOLD) }
    end

    sig { params(text: String, ansi: String, bold: T::Boolean).returns(String) }
    def self.color(text, ansi, bold: false)
      prefix = bold ? "#{ansi}#{BOLD}" : ansi
      "#{prefix}#{text}#{RESET}"
    end

    private_class_method :highlight_sql, :color
  end
end
