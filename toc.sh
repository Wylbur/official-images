#!/usr/bin/env bash
set -Eeuo pipefail

self="$(basename "$0")"
usage() {
	cat <<-EOU
		usage: $self path/to/markdown.md
		   eg: $self README.md

		WARNING: this will *always* clobber any path/to/markdown.md.{toc,bak} while processing; use with caution!
	EOU
}

markdown="${1:-}"
if ! shift || [ ! -s "$markdown" ]; then usage >&2; exit 1; fi

# see https://gist.github.com/tianon/75e267d9137b1c2978031b66b3a98987 for an insane test case for this (with several rough edges)

jq --raw-input --null-input --raw-output '
	reduce inputs as $line ({ toc: "" };
		if $line | test("^```") then
			.ignore |= not
		else . end
		| if .ignore then . else
			(
				$line
				| capture("^(?<hash>#+)[[:space:]]*(?<heading>.*?)[[:space:]]*$")
				// null
			) as $cap
			| if $cap then
				($cap.hash | length) as $level
				| .levels[$level] += 1
				| .levels |= (.[range($level+1; length)] = 0)
				| (
					$cap.heading
					| ascii_downcase
					# https://github.com/thlorenz/anchor-markdown-header/blob/6b9bc1c902e48942666859fb6f795d91cbfd48e7/anchor-markdown-header.js#L33-L48
					| gsub(" "; "-")
					# escape codes (commented out because this is not something GitHub strips, although it *does* strip % which is not included below, so that is added here)
					#| gsub("%[abcdef0-9]{2}"; ""; "i")
					| gsub("%"; "")
					# single chars that are removed
					| gsub("[\\\\/?!:\\[\\]`.,()*\"'"'"';{}+=<>~$|#@&–—]"; "")
					# CJK punctuations that are removed
					| gsub("[。？！，、；：“”【】（）〔〕［］﹃﹄“ ”‘’﹁﹂—…－～《》〈〉「」]"; "")
					# Strip emojis (*technically* this is way too aggressive and will strip out *all* UTF-8, but 🤷)
					| (split("") | map(select(utf8bytelength == 1)) | join(""))
					# TODO Strip embedded markdown formatting
				) as $anchor
				# handle repetition (same end anchor)
				| (
					(.seen // []) as $seen
					| first(
						# this 1000 limits how many repeated headings we can have, but 1000 of the exact same header text seems pretty generous 🙊
						$anchor + (range(1000) | if . > 0 then "-\(.)" else "" end)
						| select(IN($seen[]) | not)
					)
					// error("repetition level too deep on #\($anchor) (\($line)) at line \(input_line_number)")
				) as $finalAnchor
				| .toc += "\("\t" * ($level-1) // "")\(.levels[$level]).\t[\($cap.heading)](#\($finalAnchor))\n"
				| .seen += [ $finalAnchor ]
			else . end
		end
	)
	| .toc
' "$markdown" > "$markdown.toc"

gawk -v tocFile="$markdown.toc" '
	/^<!-- AUTOGENERATED TOC -->$/ {
		inToc = !inToc
		seenToc = 1
		if (inToc) {
			print
			print ""
			system("cat " tocFile)
			# no need for another newline because tocFile should already end with one
			print
		}
		next
	}
	!inToc { print }
' "$markdown" > "$markdown.bak"

mv -f "$markdown.bak" "$markdown"
rm -f "$markdown.toc"
