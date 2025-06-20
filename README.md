# Ruby LLM Evals

This POC aims to demonstrate a simple DIY approach to writing [evals](https://www.datacamp.com/blog/llm-evaluation) to aid in the iteration of LLM prompts and outputs.

While there are growing numbers of frameworks and SaaS offerings in the evals space, the underlying idea is simple enough that it makes sense to at least experiment with a homegrown approach.

The AI-assisted artwork batch imports in https://github.com/artsy/volt provides a convenient test case for this.

<video src="https://github.com/user-attachments/assets/cd55fd3d-63f1-45d4-ad5a-9739ee711690"></video>

## Setup

Clone the repo:

```sh
git clone https://github.com/anandaroop/ruby-llm-evals/
```

Set up API keys:

```sh
cp .env.example .env
```

And replace the placeholders^ there with the corresponding **API Key** values from the [1password entry for the ol' Innovation Squad](https://start.1password.com/open/i?a=7P2276AIKNH45NNGS7ZQZMI6XE&v=dblyinpit6u77a4ksc2tgt2hgu&i=ua7lfrl3wll4kd6etiln54th34&h=team-artsy.1password.com)

## Usage

### Run the evals

```sh
ruby eval.rb
```

For this POC, just about everything lives in the top-level `eval.rb` file.

By default it

- loads up a [tiny slice](files/granary-tiny.csv) of one partner's custom CSV format
- creates a system prompt and a user prompt
- selects an LLM model
- prompts the selected LLM with the data
- evaluates the results

If you want to iterate, change any of these things directly in the script and re-run `ruby eval.rb`.

### View the results

```sh
ls results

cat results/artwork_imports_eval_20250614_012629.yaml # e.g.
```

By default the result of the evaluation will be saved to a timestamped YAML file at `results/artwork_imports_eval_YYYYMMDD_HHMMSS.yaml`

This allows the entire context of the evaluation to be saved for examination or comparison — csv data, model/vendor choice, system prompt, user prompt, evaluation results.

I've committed a few representative examples (which were run against the [full csv](files/granary-full.csv) not the tiny one) so that you can…

### Compare results of previous runs

```sh
ruby analyze.rb
```

Turns out Claude is good at generating fancy CLI based visualizations, so that's what this will do. View the screencap above to see what this looks like.

## TODO

- [x] **Document**: Write an actual README.
- [ ] **Reorganize**: For simplicity I dumped (almost) everything into a single Ruby script. This could all be structured better via Rake tasks or a proper CLI or something.
- [ ] **Expand**: I included one partner's custom CSV format, and nothing from the PDF side of things. So there's more that could be done here.
- [ ] **Iterate**: I just pulled the various eval metrics here out of thin air. Nothing here is sacred — everything is up for modification.
