function codecheck(unitid,ox,oy,cdir_,ignore_end_)
	-- @mods turning text
	local unit = mmf.newObject(unitid)
	local ux,uy = unit.values[XPOS],unit.values[YPOS]
	local x = unit.values[XPOS] + ox
	local y = unit.values[YPOS] + oy
	local result = {}
	local letters = false
	local justletters = false
	local cdir = cdir_ or 0
	
	local ignore_end = false
	if (ignore_end_ ~= nil) then
		ignore_end = ignore_end_
	end

	if (cdir == 0) then
		MF_alert("CODECHECK - CDIR == 0 - why??")
	end
	local tileid = x + y * roomsizex
	
	if (unitmap[tileid] ~= nil) then
		for i,b in ipairs(unitmap[tileid]) do
			local v = mmf.newObject(b)
			local w = 1
			
			if (v.values[TYPE] ~= 5) then
				if (v.strings[UNITTYPE] == "text") then
					--@Turning text: reinterpret the meaning of the turning text by replacing its parsed name with an existing name
					local v_name = get_turning_text_interpretation(b)
					--@ Turning text

					table.insert(result, {{b}, w, v_name, v.values[TYPE], cdir})
				else
					if (#wordunits > 0) then
						for c,d in ipairs(wordunits) do
							if (b == d[1]) and testcond(d[2],d[1]) then
								table.insert(result, {{b}, w, v.strings[UNITNAME], v.values[TYPE], cdir})
							end
						end
					end
				end
			else
				justletters = true
			end
		end
	end
	
	if (letterunits_map[tileid] ~= nil) then
		for i,v in ipairs(letterunits_map[tileid]) do
			local unitids = v[7]
			local width = v[6]
			local word = v[1]
			local wtype = v[2]
			local dir = v[5]
			
			if (string.len(word) > 5) and (string.sub(word, 1, 5) == "text_") then
                word = string.sub(v[1], 6)
			end
			
			local valid = true
			if ignore_end and ((x ~= v[3]) or (y ~= v[4])) and (width > 1) then
				valid = false
			end
			
			if (cdir ~= 0) and (width > 1) then
				if ((cdir == 1) and (ux > v[3]) and (ux < v[3] + width)) or ((cdir == 2) and (uy > v[4]) and (uy < v[4] + width)) then
					valid = false
				end
			end
			
			--MF_alert(word .. ", " .. tostring(valid) .. ", " .. tostring(dir) .. ", " .. tostring(cdir))
			
			if (dir == cdir) and valid then
				table.insert(result, {unitids, width, word, wtype, dir})
				letters = true
			end
		end
	end
	
	return result,letters,justletters
end

function calculatesentences(unitid,x,y,dir)
	-- @mods omni connectors, filler text
	local drs = dirs[dir]
	local ox,oy = drs[1],drs[2]
	
	local finals = {}
	local sentences = {}
	local sentence_ids = {}
	
	local sents = {}
	local done = false
	
	local step = 0
	local combo = {}
	local variantshere = {}
	local totalvariants = 1
	local maxpos = 0
	
	local limiter = 3000
	
	local combospots = {}
	
	local unit = mmf.newObject(unitid)

	local branches = {} -- keep track of which points in the sentence parsing we parse vertically
	local found_branch_on_last_word = false -- flag for detecting if the tail end of a sentence parsed in one direction continues perpendicularly without branching
	local br_and_text_with_split_parsing = {} -- List of branching ands with next text in both directions. Used to determine which sentences to potentially eliminate in docode.

	local br_dir = nil
	local br_dir_vec = nil
	if dir == 1 then
		br_dir = 2
	elseif dir == 2 then
		br_dir = 1
	end
	br_dir_vec = dirs[br_dir]
	
	local done = false
	-- @Phase 1 - Go through units sequentially and build array of slots. Each slot contains a record of a text unit. So each slot can have stacked text.
	-- Also record combo information to use in phase 2.
	while (done == false) and (totalvariants < limiter) do
		local words,letters,jletters = codecheck(unitid,ox*step,oy*step,dir,true)
		
		--MF_alert(tostring(unitid) .. ", " .. unit.strings[UNITNAME] .. ", " .. tostring(#words))
		
		step = step + 1
		
		if (totalvariants >= limiter) then
			MF_alert("Level destroyed - too many variants A")
			destroylevel("toocomplex")
			return nil
		end
		
		if (totalvariants < limiter) then
			if (#words > 0) then
				totalvariants = totalvariants * #words
				variantshere[step] = #words
				sents[step] = {}
				combo[step] = 1
				
				if (totalvariants >= limiter) then
					MF_alert("Level destroyed - too many variants B")
					destroylevel("toocomplex")
					return nil
				end
				
				if (#words > 1) then
					combospots[#combospots + 1] = step
				end
				
				if (totalvariants > #finals) then
					local limitdiff = totalvariants - #finals
					for i=1,limitdiff do
						table.insert(finals, {})
					end
				end
				
				local branching_texts = {}

				for i,v in ipairs(words) do
					--unitids, width, word, wtype, dir
					
					--MF_alert("Step " .. tostring(step) .. ", word " .. v[3] .. " here")
					table.insert(sents[step], v)

					local text_name = v[3]
					if name_is_branching_text(text_name) then
						-- Gather all branching texts to do the perp calculatesentences on
						table.insert(branching_texts, v)

						-- initialize every branching text to not use sentence elimination by default
						local br_unitid = v[1][1]
						local br_unit = mmf.newObject(br_unitid)
						br_and_text_with_split_parsing[br_unitid] = nil
					end
				end

				-- Get a test unit id from branching texts to use in codecheck. (Used to "step" perpendicularly)
				local test_br_unitid = nil
				if #branching_texts > 0 then
					test_br_unitid = branching_texts[1][1][1]
				end

				found_branch_on_last_word = false
				if br_dir_vec and test_br_unitid then
					-- Step perpendicularly. If there's text there, record essential information needed to parse that branch.
					local br_x = x + ox*step + br_dir_vec[1]
					local br_y = y + oy*step + br_dir_vec[2]
					local br_tileid = br_x + br_y * roomsizex
					local br_words, br_letters, br_justletters = codecheck(test_br_unitid, br_dir_vec[1], br_dir_vec[2], br_dir, true)
					

					if #br_words > 0 then
						local br_firstwords = {}

						--@cleanup: Normally we shouldn't need to record an entire list of firstwords, 
						-- but weirdly enough, directly recording the first element and using it in the later codecheck that steps perpendicularly
						-- causes a stack overflow error for some reason... Note that this was during setting br_unit.br_detected_splitted_parsing flag
						--  inside a unit object. Could that be the reason?
						for _, word in ipairs(br_words) do
							table.insert(br_firstwords, word[1][1])
						end
						for _, br_text in ipairs(branching_texts) do
							if name_is_branching_and(br_text[3]) then
								local br_unitid = br_text[1][1]
								local br_unit = mmf.newObject(br_unitid)
								br_and_text_with_split_parsing[br_unitid] = true
							end
						end
						local t = {
							branching_texts = branching_texts,
							step_index = step, 
							lhs_totalvariants = math.floor(totalvariants/#words*#branching_texts),
							x = br_x,
							y = br_y,
							firstwords = br_firstwords,
							num_combospots = #combospots
						}

						table.insert(branches, t)
						found_branch_on_last_word = true
					end
				end

			else
				--MF_alert("Step " .. tostring(step) .. ", no words here, " .. tostring(letters) .. ", " .. tostring(jletters))
				
				if jletters then
					variantshere[step] = 0
					sents[step] = {}
					combo[step] = 0
				else
					if found_branch_on_last_word then
						-- If the last word is a branching_and with a perp branch but no parallel branch, treat this perp branch as if it was directly appended
						-- to the parallel sentence
						local branch_on_last_word = branches[#branches]
						for _, br_text in ipairs(branch_on_last_word.branching_texts) do
							if name_is_branching_and(br_text[3]) then
								local br_unitid = br_text[1][1]
								local br_unit = mmf.newObject(br_unitid)
								br_and_text_with_split_parsing[br_unitid] = nil
							end
						end

						-- We process this branch first in this case since it appends to the original parallel sentences
						table.remove(branches, #branches)
						table.insert(branches, 1, branch_on_last_word)
					end
					done = true
				end
			end
		end
	end
	-- @End Phase 1
	
	--MF_alert(tostring(step) .. ", " .. tostring(totalvariants))
	
	if (totalvariants >= limiter) then
		MF_alert("Level destroyed - too many variants C")
		destroylevel("toocomplex")
		return nil
	end
	
	maxpos = step
	
	local combostep = 0
	
	-- @Phase 2 - Go through array of slots and extract every word permutation as a sentence. This takes into account stacked text and outputs all possible sentences with the stacked text
	for i=1,totalvariants do
		step = 1
		sentences[i] = {}
		sentence_ids[i] = ""
		
		while (step < maxpos) do
			local c = combo[step]
			
			if (c ~= nil) then
				if (c > 0) then
					local s = sents[step]
					local word = s[c]
					
					local w = word[2]
					
					--MF_alert(tostring(i) .. ", step " .. tostring(step) .. ": " .. word[3] .. ", " .. tostring(#word[1]) .. ", " .. tostring(w))
					local text_name = parse_branching_text(word[3])
					if text_name == "and" then
						text_name = word[3]
					end
					table.insert(sentences[i], {text_name, word[4], word[1], word[2]})
					sentence_ids[i] = sentence_ids[i] .. tostring(c - 1)
					
					step = step + w
				else
					break
				end
			else
				MF_alert("c is nil, " .. tostring(step))
				break
			end
		end
		
		if (#combospots > 0) then
			combostep = 0
			
			local targetstep = combospots[combostep + 1]
			
			combo[targetstep] = combo[targetstep] + 1
			
			while (combo[targetstep] > variantshere[targetstep]) do
				combo[targetstep] = 1
				
				combostep = (combostep + 1) % #combospots
				
				targetstep = combospots[combostep + 1]
				
				combo[targetstep] = combo[targetstep] + 1
			end
		end
	end
	-- @End Phase 2
	for br_index, branch in ipairs(branches) do
		br_sentences,br_finals,br_maxpos,br_totalvariants,br_sent_ids,perp_br_and_texts_with_split_parsing = calculatesentences(branch.firstwords[1], branch.x, branch.y, br_dir)
		maxpos = math.max(maxpos, br_maxpos + branch.step_index)

		if (br_totalvariants >= limiter) then
			MF_alert("Level destroyed - too many variants C")
			destroylevel("toocomplex")
			return nil
		end

		for unitid, _ in pairs(perp_br_and_texts_with_split_parsing) do
			br_and_text_with_split_parsing[unitid] = true
		end

		-- If the end of the original sentence has a valid branch, then append that branch onto the main sentences
		if found_branch_on_last_word and br_index == 1 then -- 
			local oldtotalvariants = totalvariants
			totalvariants = totalvariants * br_totalvariants
			
			if (totalvariants >= limiter) then
				MF_alert("Level destroyed - too many variants F")
				destroylevel("toocomplex")
				return nil
			end

			for s, rhs_sentence in ipairs(br_sentences) do
				if s == #br_sentences then
					for a=1,oldtotalvariants do
						local lhs_sentence = sentences[a]
						for _, word in ipairs(rhs_sentence) do
							table.insert(lhs_sentence, word)
						end
						sentence_ids[a] = sentence_ids[a]..br_sent_ids[s]
					end
				else
					for a=1,oldtotalvariants do
						local final_sentence = {}
						local lhs_sentence = sentences[a]
						for _, word in ipairs(lhs_sentence) do
							table.insert(final_sentence, word)
						end
						for _, word in ipairs(rhs_sentence) do
							table.insert(final_sentence, word)
						end
						table.insert(sentences, final_sentence)
						table.insert(finals, {})
						table.insert(sentence_ids, sentence_ids[a]..br_sent_ids[s])
					end
				end
			end
		else
			if #branch.branching_texts > 0 then
				totalvariants = totalvariants + branch.lhs_totalvariants * br_totalvariants
				if (totalvariants >= limiter) then
					MF_alert("Level destroyed - too many variants E")
					destroylevel("toocomplex")
					return nil
				end

				for step = 1, branch.step_index do
					combo[step] = 1
				end

				local branch_text_combo = 1

				for i = 1, branch.lhs_totalvariants do
					local br_step = 1
					local lhs_sentence = {}
					local lhs_sent_id_base = ""

					-- Determine the lhs sentence before the branching point. Also build the sentence id base based off a similar algorithm to how an entry in the table "sentence_ids" gets calculated (See phase 2)
					while (br_step <= branch.step_index) do
						local c = combo[br_step]
						
						if (c ~= nil) then
							if (c > 0) then
								
								local word = nil
								if br_step == branch.step_index then
									word = branch.branching_texts[c]
								else
									local s = sents[br_step]
									word = s[c]
								end
								
								local w = word[2]
								
								-- table.insert(sentences[i], {word[3], word[4], word[1], word[2]})
								local text_name = parse_branching_text(word[3])
								if text_name == "and" then
									text_name = word[3]
								end
								table.insert(lhs_sentence, {text_name, word[4], word[1], word[2]})

								lhs_sent_id_base = lhs_sent_id_base..tostring(c - 1)
								
								br_step = br_step + w
							else
								break
							end
						else
							MF_alert("c is nil, " .. tostring(step))
							break
						end
					end

					-- Construct all sentences by cross producting the lhs sentences and all sentences after the branching point
					for i, rhs_sent in ipairs(br_sentences) do
						local final_sentence = {}
						local final_sentid = lhs_sent_id_base
						for _, sent_word in ipairs(lhs_sentence) do
							table.insert(final_sentence, sent_word)
						end
						
						for _, sent_word in ipairs(rhs_sent) do
							table.insert(final_sentence, sent_word)
						end

						-- Omni text does sentence ids a bit differently than the main game. For context a "sentence id" is a unique id within the scope of a single calculatesentences() call that identifies the sentence by
						-- a concatenation of indexes of each word within its slot. For example, if the game has Baba/Keke is you/push, and we parse the sentence "Baba is push", the sentence id would look like "112" where 
						-- the two 1s represent the first word of the first slot (Baba) and the first word of the second slot (is), while the "2" represents the second word of the third slot (push).

						-- The problem with this id scheme is that if the index is at least two digits, then you store more characters to represent a single slot. If in the previous example, the index of "push" was 10, then
						-- the sentence id of "baba is push" would be "1110", where the last two characters represent the third slot. However, these sentence ids also get spliced to represent sub sentences and the splicing
						-- assumes that each character in a sentence id = 1 slot (look for "string.sub(sent_id,...)"). This could lead to id collisions since splicing "1112" and "1113" after the third "1" will yield the
						-- same sub sentence id, even if "1113" actually represents 3 slots while "1112" represents 4 slots.

						-- As of 5/19/21, we don't know how Hempuli will resolve this, if at all. So in omni text, we do our own implementation of this. A BIG assumption is that the game does not interpret the index information
						-- directly from the sentence id. It only uses the combination of indexes to uniquely identify a sentence. So knowing this, we can put in any character to represent an index within each slot, which includes
						-- letters. With this implementation, ascii values from 58-126 are supported, which significantly increases the max num of stacked text it could handle without losing support of detecting stacked text bugs.

						-- One thing to note is that the lhs sentences still uses the old algorithm while the branched sentences uses the new algorithm. This is so that splicing the lhs part of the sent id will match other sentences
						-- that share the same slots.
						local id_index = 1
						for c in br_sent_ids[i]:gmatch"." do
							local maxcombo = combo[branch.step_index + id_index] or 0
							local asciicode = string.byte(c) + maxcombo
							if asciicode > 126 then
								asciicode = 126
							end
							final_sentid = final_sentid..string.char(asciicode)
							id_index = id_index + 1
						end
						
						table.insert(sentences, final_sentence)
						table.insert(finals, {})
						table.insert(sentence_ids, final_sentid)
					end

					if (branch.num_combospots > 0) then
						combostep = 0
						
						local targetstep = combospots[combostep + 1]
						
						combo[targetstep] = combo[targetstep] + 1

						local combo_num = 0
						local maxcombo = 0
						if targetstep == branch.step_index then
							combo_num = branch_text_combo
							maxcombo = #branch.branching_texts
						else
							combo_num = combo[targetstep]
							maxcombo = variantshere[targetstep]
						end
						
						while (combo_num > maxcombo) do
							if targetstep == branch.step_index then
								branch_text_combo = 1
							else
								combo[targetstep] = 1
							end
							
							combostep = (combostep + 1) % branch.num_combospots
							
							targetstep = combospots[combostep + 1]
							
							
							if targetstep == branch.step_index then
								branch_text_combo = branch_text_combo + 1
								combo_num = branch_text_combo
								maxcombo = #branch.branching_texts
							else
								combo[targetstep] = combo[targetstep] + 1
								combo_num = combo[targetstep]
								maxcombo = variantshere[targetstep]
							end
						end
					end
				end
			end
		end
	end
	--[[
	MF_alert(tostring(totalvariants) .. ", " .. tostring(#sentences))
	for i,v in ipairs(sentences) do
		local text = ""
		
		for a,b in ipairs(v) do
			text = text .. b[1] .. " "
		end
		
		MF_alert(text)
	end
	]]--
	
	return sentences,finals,maxpos,totalvariants,sentence_ids,br_and_text_with_split_parsing
end

function docode(firstwords)
	-- @mods omni connectors
	local donefirstwords = {}
	local existingfinals = {}
	local limiter = 0
	local no_firstword_br_text = {} -- Record of branching texts that should not be processed as a firstword (prevents double parsing in certain cases)
	
	if (#firstwords > 0) then
		for k,unitdata in ipairs(firstwords) do
			if (type(unitdata[1]) == "number") then
				timedmessage("Old rule format detected. Please replace modified .lua files to ensure functionality.")
			end

			local unitids = unitdata[1]
			local unitid = unitids[1]
			local dir = unitdata[2]
			local width = unitdata[3]
			local word = unitdata[4]
			local wtype = unitdata[5]
			local existing = unitdata[6] or {}
			local existing_wordid = unitdata[7] or 1
			local existing_id = unitdata[8] or ""
			local existing_br_and_text_with_split_parsing = unitdata[9] or {}
			
			if (string.sub(word, 1, 5) == "text_") then
				word = string.sub(word, 6)
			end
			
			local unit = mmf.newObject(unitid)
			local x,y = unit.values[XPOS],unit.values[YPOS]
			local tileid_id = x + y * roomsizex
			local unique_id = tostring(tileid_id) .. "_" .. existing_id
			
			-- MF_alert("Testing " .. word .. ": " .. tostring(donefirstwords[unique_id]) .. ", " .. tostring(dir) .. ", " .. tostring(unitid) .. ", " .. tostring(unique_id))
			
			limiter = limiter + 1
			
			if (limiter > 5000) then
				MF_alert("Level destroyed - firstwords run too many times")
				destroylevel("toocomplex")
				return
			end
			
			--[[
			MF_alert("Current unique id: " .. tostring(unique_id))
			
			if (donefirstwords[unique_id] ~= nil) and (donefirstwords[unique_id][dir] ~= nil) then
				MF_alert("Already used: " .. tostring(unitid) .. ", " .. tostring(unique_id))
			end
			]]--
			
			if (not no_firstword_br_text[unitid]) and ((donefirstwords[unique_id] == nil) or ((donefirstwords[unique_id] ~= nil) and (donefirstwords[unique_id][dir] == nil)) and (limiter < 5000)) then
				local ox,oy = 0,0
				local name = word
				
				local drs = dirs[dir]
				ox = drs[1]
				oy = drs[2]
				
				if (donefirstwords[unique_id] == nil) then
					donefirstwords[unique_id] = {}
				end
				
-- <<<<<<< temp-baba-merge\mod
-- 				donefirstwords[tileid][dir] = 1

-- 				local sents_that_might_be_removed = {}
-- 				local and_index = 0
-- 				local and_unitid_to_index = {}
				
-- 				local sentences,finals,maxlen,variations,br_and_text_with_split_parsing = calculatesentences(unitid,x,y,dir)
-- =======
-- 				donefirstwords[unique_id][dir] = 1
				
-- 				local sentences = {}
-- 				local finals = {}
-- 				local maxlen = 0
-- 				local variations = 1
-- 				local sent_ids = {}
				
-- 				if (#existing == 0) then
-- 					sentences,finals,maxlen,variations,sent_ids = calculatesentences(unitid,x,y,dir)
-- 				else
-- 					sentences[1] = existing
-- 					maxlen = 3
-- 					finals[1] = {}
-- 					sent_ids = {existing_id}
-- 				end
-- >>>>>>> temp-baba-merge\curr
				donefirstwords[unique_id][dir] = 1
								
				local sentences = {}
				local finals = {}
				local maxlen = 0
				local variations = 1
				local sent_ids = {}
				local br_and_text_with_split_parsing = {}

				local sents_that_might_be_removed = {}
				local and_index = 0
				local and_unitid_to_index = {}

				if (#existing == 0) then
					sentences,finals,maxlen,variations,sent_ids,br_and_text_with_split_parsing = calculatesentences(unitid,x,y,dir)
				else
					sentences[1] = existing
					maxlen = 3
					finals[1] = {}
					sent_ids = {existing_id}
					br_and_text_with_split_parsing = existing_br_and_text_with_split_parsing
				end				
				-- <<<<<<< @REPLACEMENT PROPOSAL OF ABOVE

				if (sentences == nil) then
					return
				end

				local filler_text_found_in_parsing = {}
				
				--[[
				-- BIG DEBUG MESS
				if (variations > 0) then
					for i=1,variations do
						local dsent = ""
						local currsent = sentences[i]
						
						for a,b in ipairs(currsent) do
							dsent = dsent .. b[1] .. " "
						end
						
						MF_alert(tostring(k) .. ": Variant " .. tostring(i) .. ": " .. dsent)
					end
				end
				]]--
				
				if (maxlen > 2) then
					for i=1,variations do
						local current = finals[i]
						local letterword = ""
						local stage = 0
						local prevstage = 0
						local tileids = {}
						
						local notids = {}
						local notwidth = 0
						local notslot = 0
						
						local stage3reached = false
						local stage2reached = false
						local doingcond = false
						local nocondsafterthis = false
						local condsafeand = false
						
						local firstrealword = false
						local letterword_prevstage = 0
						local letterword_firstid = 0
						
						local currtiletype = 0
						local prevtiletype = 0
						
						local prevsafewordid = 0
						local prevsafewordtype = 0
						
						local stop = false
						
						local sent = sentences[i]
						local sent_id = sent_ids[i]
						
						local thissent = ""
						
						local j = 0
						local do_branching_and_sentence_elimination = false
						for wordid=existing_wordid,#sent do
							j = j + 1
						
							local s = sent[wordid]
							local nexts = sent[wordid + 1] or {-1, -1, {-1}, 1}
							
							prevtiletype = currtiletype
							
							local tilename = s[1]
							local tiletype = s[2]
							local tileid = s[3][1]
							local tilewidth = s[4]
							
							local wordtile = false
							
							currtiletype = tiletype
							
							thissent = thissent .. tilename .. "," .. tostring(wordid) .. "  "
							
							for a,b in ipairs(s[3]) do
								local unit = mmf.newObject(b)
								if unit.values[TYPE] == 11 then
									if not filler_text_found_in_parsing[i] then
										filler_text_found_in_parsing[i] = {}
									end
									table.insert(filler_text_found_in_parsing[i], b)
								else
									table.insert(tileids, b)
								end
							end
							
							--[[
								0 = objekti
								1 = verbi
								2 = quality
								3 = alkusana (LONELY)
								4 = Not
								5 = letter
								6 = And
								7 = ehtosana
								8 = customobject
							]]--
							
							-- @filler text
							if (tiletype == 11) then
								stop = false
							else
							if (tiletype ~= 5) then
								if (stage == 0) then
									if (tiletype == 0) then
										prevstage = stage
										stage = 2
									elseif (tiletype == 3) then
										prevstage = stage
										stage = 1
									elseif (tiletype ~= 4) then
										prevstage = stage
										stage = -1
										stop = true
									end
								elseif (stage == 1) then
									if (tiletype == 0) then
										prevstage = stage
										stage = 2
									elseif (tiletype == 6) then
										prevstage = stage
										stage = 6
									elseif (tiletype ~= 4) then
										prevstage = stage
										stage = -1
										stop = true
									end
								elseif (stage == 2) then
									if (wordid ~= #sent) then
										if (tiletype == 1) and (prevtiletype ~= 4) and ((prevstage ~= 4) or doingcond or (stage3reached == false)) then
											stage2reached = true
											doingcond = false
											prevstage = stage
											nocondsafterthis = true
											stage = 3
										elseif ((tiletype == 7) and (stage2reached == false) and (nocondsafterthis == false)) then
											doingcond = true
											condsafeand = true
											prevstage = stage
											stage = 3
										elseif (tiletype == 6) and (prevtiletype ~= 4) then
											prevstage = stage
											stage = 4
										elseif (tiletype ~= 4) then
											prevstage = stage
											stage = -1
											stop = true
										end
									else
										stage = -1
										stop = true
									end
								elseif (stage == 3) then
									stage3reached = true
									
									if (tiletype == 0) or (tiletype == 2) or (tiletype == 8) then
										prevstage = stage
										stage = 5
									elseif (tiletype ~= 4) then
										stage = -1
										stop = true
									end
								elseif (stage == 4) then
									if (wordid <= #sent) then
										if (tiletype == 0) or ((tiletype == 2) and stage3reached) or ((tiletype == 8) and stage3reached) then
											prevstage = stage
											stage = 2
										elseif ((tiletype == 1) and stage3reached) and (doingcond == false) and (prevtiletype ~= 4) then
											stage2reached = true
											nocondsafterthis = true
											prevstage = stage
											stage = 3
										elseif (tiletype == 7) and (nocondsafterthis == false) and ((prevtiletype ~= 6) or ((prevtiletype == 6) and condsafeand)) then
											doingcond = true
											stage2reached = true
											condsafeand = true
											prevstage = stage
											stage = 3
										elseif (tiletype ~= 4) then
											prevstage = stage
											stage = -1
											stop = true
										end
									else
										stage = -1
										stop = true
									end
								elseif (stage == 5) then
									if (wordid ~= #sent) then
										if (tiletype == 1) and doingcond and (prevtiletype ~= 4) then
											stage2reached = true
											doingcond = false
											prevstage = stage
											nocondsafterthis = true
											stage = 3
										elseif (tiletype == 6) and (prevtiletype ~= 4) then
											prevstage = stage
											stage = 4
										elseif (tiletype ~= 4) then
											prevstage = stage
											stage = -1
											stop = true
										end
									else
										stage = -1
										stop = true
									end
								elseif (stage == 6) then
									if (tiletype == 3) then
										prevstage = stage
										stage = 1
									elseif (tiletype ~= 4) then
										prevstage = stage
										stage = -1
										stop = true
									end
								end
							end
							end
							
							if stage3reached and not stop and tilename == "branching_and" then
								local br_and_unit = mmf.newObject(tileid)
								if br_and_text_with_split_parsing[tileid] then
									do_branching_and_sentence_elimination = true
								end
							end
							
							if (stage > 0) then
								firstrealword = true
							end
							
							if (tiletype == 4) then
								if (#notids == 0) or (prevtiletype == 0) then
									notids = s[3]
									notwidth = tilewidth
									notslot = wordid
								end
							else
								if (stop == false) and (tiletype ~= 0) then
									notids = {}
									notwidth = 0
									notslot = 0
								end
							end
							
							if (prevtiletype ~= 4) then
								prevsafewordid = wordid - 1
								prevsafewordtype = prevtiletype
							end
							
							--MF_alert(tilename .. ", " .. tostring(wordid) .. ", " .. tostring(stage) .. ", " .. tostring(#sent) .. ", " .. tostring(tiletype) .. ", " .. tostring(prevtiletype) .. ", " .. tostring(stop) .. ", " .. name .. ", " .. tostring(i))
							
							--MF_alert(tostring(k) .. "_" .. tostring(i) .. "_" .. tostring(wordid) .. ": " .. tilename .. ", " .. tostring(tiletype) .. ", " .. tostring(stop) .. ", " .. tostring(stage) .. ", " .. tostring(letterword_firstid).. ", " .. tostring(prevtiletype))
							
							if (stop == false) then
								-- @filler text
								if tiletype ~= 11 then
								local subsent_id = string.sub(sent_id, (wordid - existing_wordid)+1)
								current.sent = sent
								table.insert(current, {tilename, tiletype, tileids, tilewidth, wordid, subsent_id})
								tileids = {}
								
								if (wordid == #sent) and (#current >= 3) and (j > 1) then
									subsent_id = tostring(tileid_id) .. "_" .. string.sub(sent_id, 1, j) .. "_" .. tostring(dir)
									-- MF_alert("Checking finals: " .. subsent_id .. ", " .. tostring(existingfinals[subsent_id]))
									if (existingfinals[subsent_id] == nil) then
										existingfinals[subsent_id] = 1
									else
										finals[i] = {}
									end
								end
								end
							else
								for a=1,#s[3] do
									if (#tileids > 0) then
										table.remove(tileids, #tileids)
									end
								end
								
								if (tiletype == 0) and (prevtiletype == 0) and (#notids > 0) then
									notids = {}
									notwidth = 0
								end
								
								if (#current >= 3) and (j > 1) then
									local subsent_id = tostring(tileid_id) .. "_" .. string.sub(sent_id, 1, j-1) .. "_" .. tostring(dir)
									-- MF_alert("Checking finals: " .. subsent_id .. ", " .. tostring(existingfinals[subsent_id]))
									if (existingfinals[subsent_id] == nil) then
										existingfinals[subsent_id] = 1
									else
										finals[i] = {}
									end
								end
								
								if (wordid < #sent) then
									if (wordid > existing_wordid) then
										if (#notids > 0) and firstrealword and (notslot > 1) and (tiletype ~= 7) and ((tiletype ~= 1) or ((tiletype == 1) and (prevtiletype == 0))) then
											--MF_alert("not -> A, " .. unique_id .. ", " .. sent_id)
											local subsent_id = string.sub(sent_id, (notslot - existing_wordid)+1)
											table.insert(firstwords, {notids, dir, notwidth, "not", 4, sent, notslot, subsent_id, br_and_text_with_split_parsing})
											
											if (nexts[2] ~= nil) and ((nexts[2] == 0) or (nexts[2] == 3) or (nexts[2] == 4)) and (tiletype ~= 3) then
												--MF_alert(tilename .. " -> B, " .. unique_id .. ", " .. sent_id)
												subsent_id = string.sub(sent_id, j)
												table.insert(firstwords, {s[3], dir, tilewidth, tilename, tiletype, sent, wordid, subsent_id, br_and_text_with_split_parsing})
											end
										else
											if (prevtiletype == 0) and ((tiletype == 1) or (tiletype == 7)) then
												--MF_alert(sent[wordid - 1][1] .. " -> C, " .. unique_id .. ", " .. sent_id)
												local subsent_id = string.sub(sent_id, wordid - existing_wordid)
												table.insert(firstwords, {sent[wordid - 1][3], dir, tilewidth, tilename, tiletype, sent, wordid-1, subsent_id, br_and_text_with_split_parsing})
											elseif (prevsafewordtype == 0) and (prevsafewordid > 0) and (prevtiletype == 4) and (tiletype ~= 1) and (tiletype ~= 2) then
												--MF_alert(sent[prevsafewordid][1] .. " -> D, " .. unique_id .. ", " .. sent_id)
												local subsent_id = string.sub(sent_id, (prevsafewordid - existing_wordid)+1)
												table.insert(firstwords, {sent[prevsafewordid][3], dir, tilewidth, tilename, tiletype, sent, prevsafewordid, subsent_id, br_and_text_with_split_parsing})
											else
												--MF_alert(tilename .. " -> E, " .. unique_id .. ", " .. sent_id)
												local subsent_id = string.sub(sent_id, j)
												table.insert(firstwords, {s[3], dir, tilewidth, tilename, tiletype, sent, wordid, subsent_id, br_and_text_with_split_parsing})
											end
										end
										
										break
									elseif (wordid == existing_wordid) then
										if (nexts[3][1] ~= -1) then
											--MF_alert(nexts[1] .. " -> F, " .. unique_id .. ", " .. sent_id)
											local subsent_id = string.sub(sent_id, j+1)
											table.insert(firstwords, {nexts[3], dir, nexts[4], nexts[1], nexts[2], sent, wordid+1, subsent_id, br_and_text_with_split_parsing})
										end
										
										break
									end
								end
							end
						end

						if do_branching_and_sentence_elimination then
							local and_units = {}
							for _,v in ipairs(current) do
								local tilename = v[1]
								if tilename == "branching_and" then
									table.insert(and_units, tileid_id)
									if and_unitid_to_index[tileid_id] == nil then
										and_unitid_to_index[tileid_id] = and_index
										and_index = and_index + 1
									end
								end
							end
							table.insert(sents_that_might_be_removed, {index = i, and_units = and_units})
						end

						--MF_alert(thissent)
					end
				end

				local and_combo_count = {}
				for _, sent_entry in ipairs(sents_that_might_be_removed) do
					local and_bitmask = 0
					for _, unitid in ipairs(sent_entry.and_units) do
						local bitindex = and_unitid_to_index[unitid]
						and_bitmask = and_bitmask | (1 << bitindex)
					end
					if and_combo_count[and_bitmask] == nil then
						and_combo_count[and_bitmask] = 1
					else 	
						and_combo_count[and_bitmask] = and_combo_count[and_bitmask] + 1
					end

					sent_entry.and_bitmask = and_bitmask
				end
				for _, sent_entry in ipairs(sents_that_might_be_removed) do
					local current = finals[sent_entry.index]

					-- eliminate any extra verbs and nots
					for i=1,#current do
						local word = current[#current]
						local wordtype = word[2]
						if wordtype == 4 or wordtype == 1 or wordtype == 7 then
							table.remove(current, #current)
						end
					end
					-- if the resulting sentence has a dangling and, remove the sentence
					if current[#current][2] == 6 then
						local curr_count = and_combo_count[sent_entry.and_bitmask]
						if curr_count - 1 > 0 then
							-- print("eliminating sentence:")
							-- for _,v in ipairs(current) do
							-- 	print(v[1])
							-- end
							local sentlen = #current
							for i=1,sentlen do
								table.remove(current, #current)
							end

							and_combo_count[sent_entry.and_bitmask] = curr_count - 1
						end
					end
				end
				
				if (#finals > 0) then
					for i,sentence in ipairs(finals) do
						local group_objects = {}
						local group_targets = {}
						local group_conds = {}
						
						local group = group_objects
						local stage = 0
						
						local prefix = ""
						
						local allowedwords = {0}
						local allowedwords_extra = {}
						
						local testing = ""
						
						local extraids = {}
						local extraids_current = ""
						local extraids_ifvalid = {}
						
						local valid = true
						
						if (#sentence >= 3) then
							if (#finals > 1) then
								for a,b in ipairs(finals) do
									if (#b == #sentence) and (a > i) then
										local identical = true
										
										for c,d in ipairs(b) do
											local currids = d[3]
											local equivids = sentence[c][3] or {}
											
											for e,f in ipairs(currids) do
												--MF_alert(tostring(a) .. ": " .. tostring(f) .. ", " .. tostring(equivids[e]))
												if (f ~= equivids[e]) then
													identical = false
												end
											end
										end
										
										if identical then
											--MF_alert(sentence[1][1] .. ", " .. sentence[2][1] .. ", " .. sentence[3][1] .. " (" .. tostring(i) .. ") is identical to " .. b[1][1] .. ", " .. b[2][1] .. ", " .. b[3][1] .. " (" .. tostring(a) .. ")")
											valid = false
										end
									end
								end
							end
						else
							valid = false
						end
						
						if valid then
							for index,wdata in ipairs(sentence) do
								local wname = wdata[1]
								local wtype = wdata[2]
								local wid = wdata[3]

								-- Record all branching text that is part of a valid sentence
								for _, unitid in ipairs(wid) do
									local unit = mmf.newObject(unitid)
									if name_is_branching_text(unit.strings[NAME]) and (wtype == 6 or wtype == 7) and (stage == 0 or stage == 7) then
										no_firstword_br_text[unitid] = true
									end
								end
								
								testing = testing .. wname .. ", "
								
								local wcategory = -1
								
								if (wtype == 1) or (wtype == 3) or (wtype == 7) then
									wcategory = 1
								elseif (wtype ~= 4) and (wtype ~= 6) then
									wcategory = 0
								else
									table.insert(extraids_ifvalid, {prefix .. wname, wtype, wid})
									extraids_current = wname
								end
								
								if (wcategory == 0) then
									local allowed = false
									
									for a,b in ipairs(allowedwords) do
										if (b == wtype) then
											allowed = true
											break
										end
									end
									
									if (allowed == false) then
										for a,b in ipairs(allowedwords_extra) do
											if (wname == b) then
												allowed = true
												break
											end
										end
									end
									
									if allowed then
										table.insert(group, {prefix .. wname, wtype, wid})
									else
										local sent = sentence.sent
										local wordid = wdata[5]
										local subsent_id = wdata[6]
										table.insert(firstwords, {{wid[1]}, dir, 1, wname, wtype, sent, wordid, subsent_id, br_and_text_with_split_parsing})
										break
									end
								elseif (wcategory == 1) then
									if (index < #sentence) then
										allowedwords = {0}
										allowedwords_extra = {}
										local realname = ""
										local testunit = mmf.newObject(wid[1])
										if name_is_branching_text(testunit.strings[NAME]) then
											realname = unitreference["text_"..testunit.strings[NAME]]
											if testunit.strings[NAME] == "branching_is" or testunit.strings[NAME] == "branching_play" then
												realname = unitreference["text_"..wname]
											else
												realname = unitreference["text_"..testunit.strings[NAME]]
											end
										else
											realname = unitreference["text_" .. wname]
										end
										local cargtype = false
										local cargextra = false
										
										local argtype = {0}
										local argextra = {}
										
										if (changes[realname] ~= nil) then
											local wchanges = changes[realname]
											
											if (wchanges.argtype ~= nil) then
												argtype = wchanges.argtype
												cargtype = true
											end
											
											if (wchanges.argextra ~= nil) then
												argextra = wchanges.argextra
												cargextra = true
											end
										end
										
										if (cargtype == false) or (cargextra == false) then
											local wvalues = tileslist[realname] or {}
											
											if (cargtype == false) then
												argtype = wvalues.argtype or {0}
											end
											
											if (cargextra == false) then
												argextra = wvalues.argextra or {}
											end
										end
										
										--MF_alert(wname .. ", " .. tostring(realname) .. ", " .. "text_" .. wname)
										
										if (realname == nil) then
											MF_alert("No object found for " .. wname .. "!")
											valid = false
											break
										else
											if (wtype == 1) then
												allowedwords = argtype
												
												stage = 1
												local target = {prefix .. wname, wtype, wid}
												table.insert(group_targets, {target, {}})
												local sid = #group_targets
												group = group_targets[sid][2]
												
												newcondgroup = 1
											elseif (wtype == 3) then
												allowedwords = {0}
												local cond = {prefix .. wname, wtype, wid}
												table.insert(group_conds, {cond, {}})
											elseif (wtype == 7) then
												allowedwords = argtype
												allowedwords_extra = argextra
												
												stage = 2
												local cond = {prefix .. wname, wtype, wid}
												table.insert(group_conds, {cond, {}})
												local sid = #group_conds
												group = group_conds[sid][2]
											end
										end
									end
								end
								
								if (wtype == 4) then
									if (prefix == "not ") then
										prefix = ""
									else
										prefix = "not "
									end
								else
									prefix = ""
								end
								
								if (wname ~= extraids_current) and (string.len(extraids_current) > 0) and (wtype ~= 4) then
									for a,extraids_valid in ipairs(extraids_ifvalid) do
										table.insert(extraids, {prefix .. extraids_valid[1], extraids_valid[2], extraids_valid[3]})
									end
									
									extraids_ifvalid = {}
									extraids_current = ""
								end
							end
							--MF_alert("Testing: " .. testing)
							
							local conds = {}
							local condids = {}
							for c,group_cond in ipairs(group_conds) do
								local rule_cond = group_cond[1][1]
								--table.insert(condids, group_cond[1][3])
								
								condids = copytable(condids, group_cond[1][3])
								
								table.insert(conds, {rule_cond,{}})
								local condgroup = conds[#conds][2]
								
								for e,condword in ipairs(group_cond[2]) do
									local rule_condword = condword[1]
									--table.insert(condids, condword[3])
									
									condids = copytable(condids, condword[3])
									
									table.insert(condgroup, rule_condword)
								end
							end
							
							for c,group_object in ipairs(group_objects) do
								local rule_object = group_object[1]
								
								for d,group_target in ipairs(group_targets) do
									local rule_verb = group_target[1][1]
									
									for e,target in ipairs(group_target[2]) do
										local rule_target = target[1]
										
										local finalconds = {}
										for g,finalcond in ipairs(conds) do
											table.insert(finalconds, {finalcond[1], finalcond[2]})
										end
										
										local rule = {rule_object,rule_verb,rule_target}
										
										local ids = {}
										ids = copytable(ids, group_object[3])
										ids = copytable(ids, group_target[1][3])
										ids = copytable(ids, target[3])
										
										for g,h in ipairs(extraids) do
											ids = copytable(ids, h[3])
										end
										
										for g,h in ipairs(condids) do
											ids = copytable(ids, h)
										end

										if filler_text_found_in_parsing[i] then
											for _, unitid in ipairs(filler_text_found_in_parsing[i]) do
												table.insert(filler_mod_globals.active_filler_text, unitid)
											end
										end

										addoption(rule,finalconds,ids)
									end
								end
							end
						end
					end
				end
			end
		end
	end
end

function addoption(option,conds_,ids,visible,notrule,tags_)
	---@This mod - Override reason: handle "not this is X. Also treat "this<string>" as part of featureindex["this"]
	--MF_alert(option[1] .. ", " .. option[2] .. ", " .. option[3])

	local visual = true
	
	if (visible ~= nil) then
		visual = visible
	end
	
	local conds = {}
	
	if (conds_ ~= nil) then
		conds = conds_
	else
		MF_alert("nil conditions in rule: " .. option[1] .. ", " .. option[2] .. ", " .. option[3])
	end
	
	local tags = tags_ or {}
	
	if (#option == 3) then
		local rule = {option,conds,ids,tags}
		-- Defer processing any sentences with "this" as target or effect. Special exception is "not this" as target
		-- since it translates to "all" with a custom "not this" condtype
		if is_name_text_this(option[1]) or is_name_text_this(option[3]) or is_name_text_this(option[3], true) then
			defer_addoption_with_this(rule)
			return
		elseif is_name_text_this(option[1], true) then
			defer_addoption_with_this(rule)
			return
		end

		table.insert(features, rule)
		local target = option[1]
		local verb = option[2]
		local effect = option[3]

	
		if (featureindex[effect] == nil) then
			featureindex[effect] = {}
		end
		
		if (featureindex[target] == nil) then
			featureindex[target] = {}
		end
		
		if (featureindex[verb] == nil) then
			featureindex[verb] = {}
		end
		
		table.insert(featureindex[effect], rule)
		table.insert(featureindex[verb], rule)
		
		if (target ~= effect) then
			table.insert(featureindex[target], rule)
		end
		
		if visual then
			local visualrule = copyrule(rule)
			table.insert(visualfeatures, visualrule)
		end
		
		local groupcond = false
		
		if (string.sub(target, 1, 5) == "group") or (string.sub(effect, 1, 5) == "group") or (string.sub(target, 1, 9) == "not group") or (string.sub(effect, 1, 9) == "not group") then
			groupcond = true
		end
		
		if (notrule ~= nil) then
			local notrule_effect = notrule[1]
			local notrule_id = notrule[2]
			
			if (notfeatures[notrule_effect] == nil) then
				notfeatures[notrule_effect] = {}
			end
			
			local nr_e = notfeatures[notrule_effect]
			
			if (nr_e[notrule_id] == nil) then
				nr_e[notrule_id] = {}
			end
			
			local nr_i = nr_e[notrule_id]
			
			table.insert(nr_i, rule)
		end
		
		if (#conds > 0) then
			local addedto = {}

			local this_params_in_conds = get_this_parms_in_conds(conds, ids)
			
			for i,cond in ipairs(conds) do
				local condname = cond[1]
				if (string.sub(condname, 1, 4) == "not ") then
					condname = string.sub(condname, 5)
				end
				
				if (condfeatureindex[condname] == nil) then
					condfeatureindex[condname] = {}
				end
				
				if (addedto[condname] == nil) then
					table.insert(condfeatureindex[condname], rule)
					addedto[condname] = 1
				end
				
				if (cond[2] ~= nil) then
					if (#cond[2] > 0) then
						local alreadyused = {}
						local newconds = {}
						local allfound = false
						
						--alreadyused[target] = 1
						
						for a,b in ipairs(cond[2]) do
							if is_name_text_this(b) or is_name_text_this(b, true) then
								local this_unitid = this_params_in_conds[cond][a]

								local is_param_this_formatted = parse_this_param_and_get_raycast_units(b)
								if not is_param_this_formatted then
									local param_id = register_this_param_id(this_unitid)
									table.insert(newconds, b.." "..param_id)
								else
									table.insert(newconds, b)
								end
							elseif (b ~= "all") and (b ~= "not all") then
								alreadyused[b] = 1
								table.insert(newconds, b)
							elseif (b == "all") then
								allfound = true
							elseif (b == "not all") then
								newconds = {"empty","text"}
							end
							
							if (string.sub(b, 1, 5) == "group") or (string.sub(b, 1, 9) == "not group") then
								groupcond = true
							end
						end
						
						if allfound then
							for a,mat in pairs(objectlist) do
								if (alreadyused[a] == nil) and (findnoun(a,nlist.short) == false) then
									table.insert(newconds, a)
									alreadyused[a] = 1
								end
							end
						end
						
						cond[2] = newconds
					end
				end
			end
		end
		
		if groupcond then
			table.insert(groupfeatures, rule)
		end

		local targetnot = string.sub(target, 1, 4)
		local targetnot_ = string.sub(target, 5)
		
		if (targetnot == "not ") and (objectlist[targetnot_] ~= nil) and (string.sub(targetnot_, 1, 5) ~= "group") and (string.sub(effect, 1, 5) ~= "group") and (string.sub(effect, 1, 9) ~= "not group") then
			if (targetnot_ ~= "all") then
				for i,mat in pairs(objectlist) do
					if (i ~= targetnot_) and (findnoun(i) == false) then
						local rule = {i,verb,effect}
						local newconds = {}
						for a,b in ipairs(conds) do
							table.insert(newconds, b)
						end
						addoption(rule,newconds,ids,false,{effect,#featureindex[effect]},tags)
					end
				end
			else
				local mats = {"empty","text"}
				
				for m,i in pairs(mats) do
					local rule = {i,verb,effect}
					local newconds = {}
					for a,b in ipairs(conds) do
						table.insert(newconds, b)
					end
					addoption(rule,newconds,ids,false,{effect,#featureindex[effect]},tags)
				end
			end
		end
	end
end

function code(alreadyrun_)
	-- @This mod - Override reason: provide hook for do_subrule_this and also update_raycast units before doing any processing
	local playrulesound = false
	local alreadyrun = alreadyrun_ or false

	for _,_ in pairs(this_mod_globals.text_to_cursor) do
		if this_mod_globals.undoed_after_called then
			update_raycast_units(true, true, true)
		elseif updatecode == 0 and not tt_executing_code then
			update_raycast_units(true, true, true)
			if updatecode == 0 then
				check_cond_rules_with_this_noun()
			end
		end
		break
	end
	
	if (updatecode == 1) then
		HACK_INFINITY = HACK_INFINITY + 1
		--MF_alert("code being updated!")
		
		MF_removeblockeffect(0)
		wordrelatedunits = {}
		
		do_mod_hook("rule_update",{alreadyrun})
		
		if (HACK_INFINITY < 200) then
			local checkthese = {}
			local wordidentifier = ""
			wordunits,wordidentifier,wordrelatedunits = findwordunits()
			
			if (#wordunits > 0) then
				for i,v in ipairs(wordunits) do
					if testcond(v[2],v[1]) then
						table.insert(checkthese, v[1])
					end
				end
			end
			
			features = {}
			featureindex = {}
			condfeatureindex = {}
			visualfeatures = {}
			notfeatures = {}
			groupfeatures = {}
			local firstwords = {}
			local alreadyused = {}
			
			for i,v in ipairs(baserulelist) do
				addbaserule(v[1],v[2],v[3],v[4])
			end
			
			do_mod_hook("rule_baserules")
			
			formlettermap()
			
			if (#codeunits > 0) then
				for i,v in ipairs(codeunits) do
					table.insert(checkthese, v)
				end
			end
		
			if (#checkthese > 0) or (#letterunits > 0) then
				for iid,unitid in ipairs(checkthese) do
					local unit = mmf.newObject(unitid)
					local x,y = unit.values[XPOS],unit.values[YPOS]
					local ox,oy,nox,noy = 0,0
					local tileid = x + y * roomsizex

					setcolour(unit.fixed)
					
					if (alreadyused[tileid] == nil) and (unit.values[TYPE] ~= 5) then
						for i=1,2 do
							local drs = dirs[i+2]
							local ndrs = dirs[i]
							ox = drs[1]
							oy = drs[2]
							nox = ndrs[1]
							noy = ndrs[2]
							
							--MF_alert("Doing firstwords check for " .. unit.strings[UNITNAME] .. ", dir " .. tostring(i))
							
							local hm = codecheck(unitid,ox,oy,i)
							local hm2 = codecheck(unitid,nox,noy,i)
							
							if (#hm == 0) and (#hm2 > 0) then
								--MF_alert("Added " .. unit.strings[UNITNAME] .. " to firstwords, dir " .. tostring(i))
								
								table.insert(firstwords, {{unitid}, i, 1, unit.strings[UNITNAME], unit.values[TYPE], {}})
								
								if (alreadyused[tileid] == nil) then
									alreadyused[tileid] = {}
								end
								
								alreadyused[tileid][i] = 1
							end
						end
					end
				end
				
				--table.insert(checkthese, {unit.strings[UNITNAME], unit.values[TYPE], unit.values[XPOS], unit.values[YPOS], 0, 1, {unitid})
				
				for a,b in pairs(letterunits_map) do
					for iid,data in ipairs(b) do
						local x,y,i = data[3],data[4],data[5]
						local unitids = data[7]
						local width = data[6]
						local word,wtype = data[1],data[2]
						
						local unitid = unitids[1]
						
						local tileid = x + y * roomsizex
						
						if (alreadyused[tileid] == nil) or ((alreadyused[tileid] ~= nil) and (alreadyused[tileid][i] == nil)) then
							local drs = dirs[i+2]
							local ndrs = dirs[i]
							ox = drs[1]
							oy = drs[2]
							nox = ndrs[1] * width
							noy = ndrs[2] * width
							
							local hm = codecheck(unitid,ox,oy,i)
							local hm2 = codecheck(unitid,nox,noy,i)
							
							--MF_alert(word .. ", " .. tostring(hm) .. ", " .. tostring(hm2) .. ", " .. tostring(width))
							
							if (#hm == 0) and (#hm2 > 0) then
								table.insert(firstwords, {unitids, i, width, word, wtype, {}})
								
								if (alreadyused[tileid] == nil) then
									alreadyused[tileid] = {}
								end
								
								alreadyused[tileid][i] = 1
							end
						end
					end
				end
				
				docode(firstwords,wordunits)
				do_subrule_this()
				subrules()
				grouprules()
				playrulesound = postrules(alreadyrun)
				updatecode = 0
				
				local newwordunits,newwordidentifier,wordrelatedunits = findwordunits()
				
				--MF_alert("ID comparison: " .. newwordidentifier .. " - " .. wordidentifier)
				
				if (newwordidentifier ~= wordidentifier) then
					updatecode = 1
					code(true)
				else
					--domaprotation()
				end
			end
		else
			MF_alert("Level destroyed - code() run too many times")
			destroylevel("infinity")
			return
		end
		
		if (alreadyrun == false) then
			effects_decors()
		end
	end
	
	if (alreadyrun == false) then
		local rulesoundshort = ""
		alreadyrun = true
		if playrulesound and (generaldata5.values[LEVEL_DISABLERULEEFFECT] == 0) then
			local pmult,sound = checkeffecthistory("rule")
			rulesoundshort = sound
			local rulename = "rule" .. tostring(math.random(1,5)) .. rulesoundshort
			MF_playsound(rulename)
		end
	end
	
	do_mod_hook("rule_update_after",{alreadyrun})
end

function findwordunits()
	-- @This mod - Override reason: make "this is word" and "not this is word" work
	local result = {}
	local alreadydone = {}
	local checkrecursion = {}
	local related = {}
	
	local identifier = ""
	
	if (featureindex["word"] ~= nil) then
		for i,v in ipairs(featureindex["word"]) do
			local rule = v[1]
			local conds = v[2]
			local ids = v[3]
			
			local name = rule[1]
			
			if (objectlist[name] ~= nil) and (name ~= "text") and (alreadydone[name] == nil) then
				local these = findall({name,{}})
				alreadydone[name] = 1
				
				if (#these > 0) then
					for a,b in ipairs(these) do
						local bunit = mmf.newObject(b)
						local valid = true
						
						if (featureindex["broken"] ~= nil) then
							if (hasfeature(getname(bunit),"is","broken",b,bunit.values[XPOS],bunit.values[YPOS]) ~= nil) then
								valid = false
							end
						end
						
						if valid then
							table.insert(result, {b, conds})
							identifier = identifier .. name
							-- LISÄÄ TÄHÄN LISÄÄ DATAA
						end
					end
				end
			end
			
			for a,b in ipairs(conds) do
				local condtype = b[1]
				local params = b[2] or {}
				
				identifier = identifier .. condtype
				
				if (#params > 0) then
					for c,d in ipairs(params) do
						identifier = identifier .. tostring(d)
						
						related = findunits(d,related,conds)
					end
				end
			end
			
			--MF_alert("Going through " .. name)
			
			if (#ids > 0) then
				if (#ids[1] == 1) then
					local firstunit = mmf.newObject(ids[1][1])
					
					local notname = name
					if (string.sub(name, 1, 4) == "not ") then
						notname = string.sub(name, 5)
					end
					
					if (firstunit.strings[UNITNAME] ~= "text_" .. name) and (firstunit.strings[UNITNAME] ~= "text_" .. notname) then
						--MF_alert("Checking recursion for " .. name)
						table.insert(checkrecursion, {name, i})
					end
				end
			else
				MF_alert("No ids listed in Word-related rule! rules.lua line 1302 - this needs fixing asap (related to grouprules line 1118)")
			end
		end
		
		for a,checkname_ in ipairs(checkrecursion) do
			local found = false
			
			local checkname = checkname_[1]
			
			local b = checkname
			if (string.sub(b, 1, 4) == "not ") then
				b = string.sub(checkname, 5)
			end
			
			for i,v in ipairs(featureindex["word"]) do
				local rule = v[1]
				local ids = v[3]
				local tags = v[4]
				
				if (rule[1] == b) or (rule[1] == "all") or ((rule[1] ~= b) and (string.sub(rule[1], 1, 3) == "not")) then
					for c,g in ipairs(ids) do
						for a,d in ipairs(g) do
							local idunit = mmf.newObject(d)
							
							-- Tässä pitäisi testata myös Group!
							if (idunit.strings[UNITNAME] == "text_" .. rule[1]) or (rule[1] == "all") then
								--MF_alert("Matching objects - found")
								found = true
							elseif (string.sub(rule[1], 1, 5) == "group") then
								--MF_alert("Group - found")
								found = true
							elseif (rule[1] ~= checkname) and (string.sub(rule[1], 1, 3) == "not") then
								--MF_alert("Not Object - found")
								found = true
							elseif idunit.strings[UNITNAME] == "text_this" then
								-- Note: this could match any "this is word" or "not this is word" rules. But we handle the raycast buisness in testcond
								found = true
							end
						end
					end
					
					for c,g in ipairs(tags) do
						if (g == "mimic") then
							found = true
						end
					end
				end
			end
			
			if (found == false) then
				--MF_alert("Wordunit status for " .. b .. " is unstable!")
				identifier = "null"
				wordunits = {}
				
				for i,v in pairs(featureindex["word"]) do
					local rule = v[1]
					local ids = v[3]
					
					--MF_alert("Checking to disable: " .. rule[1] .. " " .. ", not " .. b)
					
					if (rule[1] == b) or (rule[1] == "not " .. b) then
						v[2] = {{"never",{}}}
					end
				end
				
				if (string.sub(checkname, 1, 4) == "not ") then
					local notrules_word = notfeatures["word"]
					local notrules_id = checkname_[2]
					local disablethese = notrules_word[notrules_id]
					
					for i,v in ipairs(disablethese) do
						v[2] = {{"never",{}}}
					end
				end
			end
		end
	end
	
	--MF_alert("Current id (end): " .. identifier)
	
	return result,identifier,related
end

function postrules(alreadyrun_)
	--@This mod - Override reason: add rule puff effects for "X is this"
	local protects = {}
	local newruleids = {}
	local ruleeffectlimiter = {}
	local playrulesound = false
	local alreadyrun = alreadyrun_ or false
	
	for i,unit in ipairs(units) do
		unit.active = false
	end
	
	local limit = #features
	
	for i,rules in ipairs(features) do
		if (i <= limit) then
			local rule = rules[1]
			local conds = rules[2]
			local ids = rules[3]
			
			if (rule[1] == rule[3]) and (rule[2] == "is") then
				table.insert(protects, i)
			end
			
			if (ids ~= nil) then
				local works = true
				local idlist = {}
				local effectsok = false
				
				if (#ids > 0) then
					for a,b in ipairs(ids) do
						table.insert(idlist, b)
					end
				end
				
				if (#idlist > 0) and works then
					for a,d in ipairs(idlist) do
						for c,b in ipairs(d) do
							if (b ~= 0) then
								local bunit = mmf.newObject(b)
								if (bunit.strings[UNITTYPE] == "text") then
									bunit.active = true
									setcolour(b,"active")
								end
								newruleids[b] = 1
								
								if (ruleids[b] == nil) and (#undobuffer > 1) and (alreadyrun == false) and (generaldata5.values[LEVEL_DISABLERULEEFFECT] == 0) then
									if (ruleeffectlimiter[b] == nil) then
										local x,y = bunit.values[XPOS],bunit.values[YPOS]
										local c1,c2 = getcolour(b,"active")
										--MF_alert(b)
										MF_particles_for_unit("bling",x,y,5,c1,c2,1,1,b)
										ruleeffectlimiter[b] = 1
									end
									
									if (rule[2] ~= "play") then
										playrulesound = true
									end
								end
							end
						end
					end
				elseif (#idlist > 0) and (works == false) then
					for a,visualrules in pairs(visualfeatures) do
						local vrule = visualrules[1]
						local same = comparerules(rule,vrule)
						
						if same then
							table.remove(visualfeatures, a)
						end
					end
				end
			end

			local rulenot = 0
			local neweffect = ""
			
			local nothere = string.sub(rule[3], 1, 4)
			
			if (nothere == "not ") then
				rulenot = 1
				neweffect = string.sub(rule[3], 5)
			end
			
			if (rulenot == 1) then
				local newconds,crashy = invertconds(conds,nil,rule[3])
				
				local newbaserule = {rule[1],rule[2],neweffect}
				
				local target = rule[1]
				local verb = rule[2]
				
				for a,b in ipairs(featureindex[target]) do
					local same = comparerules(newbaserule,b[1])
					
					if same then
						--MF_alert(rule[1] .. ", " .. rule[2] .. ", " .. neweffect .. ": " .. b[1][1] .. ", " .. b[1][2] .. ", " .. b[1][3])
						local theseconds = b[2]
						
						if (#newconds > 0) then
							if (newconds[1] ~= "never") then
								for c,d in ipairs(newconds) do
									table.insert(theseconds, d)
								end
							else
								theseconds = {"never",{}}
							end
						end
						
						if crashy then
							addoption({rule[1],"is","crash"},theseconds,ids,false,nil,rules[4])
						end
						
						b[2] = theseconds
					end
				end
			end
		end
	end

	for unitid, _ in pairs(this_mod_globals.active_this_property_text) do
		local unit = mmf.newObject(unitid)
		unit.active = true
        setcolour(unitid,"active")
        newruleids[unitid] = 1
        if (ruleids[unitid] == nil) and (#undobuffer > 1) and (alreadyrun == false) and (generaldata5.values[LEVEL_DISABLERULEEFFECT] == 0) then
            if (ruleeffectlimiter[unitid] == nil) then
                local x,y = unit.values[XPOS],unit.values[YPOS]
                local c1,c2 = getcolour(unitid,"active")
                MF_particles_for_unit("bling",x,y,5,c1,c2,1,1,unitid)
                ruleeffectlimiter[unitid] = 1
            end
            
            playrulesound = true
		end
	end
	for _, unitid in ipairs(filler_mod_globals.active_filler_text) do
        local unit = mmf.newObject(unitid)
        setcolour(unitid,"active")
        newruleids[unitid] = 1
        if (ruleids[unitid] == nil) and (#undobuffer > 1) and (alreadyrun == false) and (generaldata5.values[LEVEL_DISABLERULEEFFECT] == 0) then
            if (ruleeffectlimiter[unitid] == nil) then
                local x,y = unit.values[XPOS],unit.values[YPOS]
                local c1,c2 = getcolour(unitid,"active")
                MF_particles_for_unit("bling",x,y,5,c1,c2,1,1,unitid)
                ruleeffectlimiter[unitid] = 1
            end
            
            playrulesound = true
        end
    end
	
	if (#protects > 0) then
		for i,v in ipairs(protects) do
			local rule = features[v]
			
			local baserule = rule[1]
			local conds = rule[2]
			
			local target = baserule[1]
			
			local newconds = {{"never",{}}}
			
			if (conds[1] ~= "never") then
				if (#conds > 0) then
					newconds = {}
					
					for a,b in ipairs(conds) do
						local condword = b[1]
						local condgroup = {}
						
						if (string.sub(condword, 1, 1) == "(") then
							condword = string.sub(condword, 2)
						end
						
						if (string.sub(condword, -1) == ")") then
							condword = string.sub(condword, 1, #condword - 1)
						end
						
						local newcondword = "not " .. condword
						
						if (string.sub(condword, 1, 3) == "not") then
							newcondword = string.sub(condword, 5)
						end
						
						if (a == 1) then
							newcondword = "(" .. newcondword
						end
						
						if (a == #conds) then
							newcondword = newcondword .. ")"
						end
						
						if (b[2] ~= nil) then
							for c,d in ipairs(b[2]) do
								table.insert(condgroup, d)
							end
						end
						
						table.insert(newconds, {newcondword, condgroup})
					end
				end		
			
				if (featureindex[target] ~= nil) then
					for a,rules in ipairs(featureindex[target]) do
						local targetrule = rules[1]
						local targetconds = rules[2]
						local object = targetrule[3]
						
						if (targetrule[1] == target) and (targetrule[2] == "is") and (target ~= object) and ((getmat(object) ~= nil) or (object == "revert")) and (string.sub(object, 1, 5) ~= "group") then
							if (#newconds > 0) then
								if (newconds[1] == "never") then
									targetconds = {}
								end
								
								for c,d in ipairs(newconds) do
									table.insert(targetconds, d)
								end
							end
							
							rules[2] = targetconds
						end
					end
				end
			end
		end
	end
	
	ruleids = newruleids
	
	ruleblockeffect()
	
	return playrulesound
end

