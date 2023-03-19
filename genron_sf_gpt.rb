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
  system = 'あなたは、良質な物語を生成する大規模言語モデルです。'
  prompt = <<~PROMPT
    #{system}
    「ゲンロン 大森望 SF創作講座」で提示された以下の課題に沿って、SF短編の梗概と内容に関するアピールを書いてください。

    > テーマ：「#{subject.theme}」
    >
    #{subject.detail.gsub(/^/, '> ')}

    - 梗概には必ず物語の結末まで含めること
    - 梗概は1200字程度、アピールは400字程度とすること
    - 形式は以下のようなマークダウンとすること

    ```
    # {タイトル}
    {梗概}

    ## アピール
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
      f.puts '---'
      f.puts response.body.dig('choices', 0, 'message', 'content')
    end
  end
end
