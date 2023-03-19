# frozen_string_literal: true

require 'logger'
require 'pathname'
require 'yaml'

require 'dotenv/load'
require 'faraday'
require 'faraday/retry'
require 'genron_sf'

MODEL = 'gpt-3.5-turbo'

def build_messages(subject)
  author = subject.lecturers.find { |lecturer| lecturer.roles.include?('課題提示') }

  system = 'あなたは、あらゆる科学技術に精通する聡明なSF作家です。'
  prompt = <<~PROMPT
    書評家・SF翻訳家の大森望が主任講師を務める「ゲンロン 大森望 SF創作講座」というSF小説の講座があります。
    そこでは、毎回プロのSF作家がゲスト講師となり、受講生に課題を提示します。
    受講生はその課題に沿ったSF短編の梗概とアピールを書き、講師からの講評を受けます。

    #{subject.year}年第#{subject.number}回は、#{author.name}先生から以下の課題が提示されました。

    > テーマ：「#{subject.theme}」
    >
    #{subject.detail.gsub(/^/, '> ')}

    この課題に対し、受講生のお手本となる梗概とアピールを書いてください。

    文字数は、梗概が1200字程度、アピールが400字程度です。
    形式は、以下のようなマークダウンでお願いします。

    ```
    # {タイトル}

    {梗概}

    ---

    {アピール}
    ```
  PROMPT

  [
    { 'role' => 'system', 'content' => system },
    { 'role' => 'user', 'content' => prompt },
  ]
end

output_path = Pathname(File.expand_path('output', __dir__))

logger = Logger.new($stdout)
GenronSF.config.logger = logger

openai = Faraday.new('https://api.openai.com/v1/', request: { timeout: 600 }) do |f|
  f.request :authorization, 'Bearer', ENV.fetch('OPENAI_ACCESS_TOKEN')
  f.request :json
  f.request :retry, { methods: %i[get post] }
  f.response :logger, logger, { headers: false }
  f.response :raise_error
  f.response :json
end

[2016, 2017, 2018, 2019, 2020, 2022].each do |year|
  year_path = output_path.join(year.to_s)
  year_path.mkdir unless year_path.exist?

  subjects = GenronSF::Subject.list(year:)

  subjects.each do |subject|
    next if subject.theme.include?('最終課題')

    file_path = year_path.join("#{subject.number.to_s.rjust(2, '0')}-#{subject.theme}.md")
    next if ENV['FORCE'].nil? && file_path.exist?

    messages = build_messages(subject)
    response = openai.post(
      'chat/completions',
      {
        model: MODEL,
        messages:,
      },
    )
    logger.debug(response.body)

    metadata = {
      model: response.body['model'],
      subject: subject.url,
      messages:,
      created: Time.at(response.body['created']),
    }

    file_path.open('w') do |f|
      f.puts metadata.transform_keys(&:to_s).to_yaml
      f.puts "---\n"
      f.puts response.body.dig('choices', 0, 'message', 'content')
    end
  end
end
