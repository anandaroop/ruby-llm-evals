# ruby-llm-evals

This is a simple, home-grown evals POC written in Ruby

## Stack

- RubyLLM as an LLM abstraction layer (See https://rubyllm.com/guides/chat)
- EasyTalk for JSON-Schema generation and validation
- json-diff for comparing JSON outputs
- Rainbow for colored terminal output
- StandardRB for code quality and formatting

## Organization

- For now, just one big kitchen-sink script at /eval.rb
- LLM judgement helper at /judge.rb
- For each test case, the results are written to a timestamped YAML file in /results

## Code conventions

- Avoid fancy meta-programming
- Use conventional-commit messages
- Before committing run linting via Standard and accept all autocorrections
