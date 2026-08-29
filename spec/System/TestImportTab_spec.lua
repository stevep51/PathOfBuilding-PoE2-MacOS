describe("ImportTab", function()
	before_each(function()
		newBuild()
	end)

	it("builds character lists for private Ruthless league names without a Ruthless tree", function()
		local importTab = build.importTab
		importTab.lastCharList = {
			{
				name = "PrivateLeagueCharacter",
				class = "Amazon",
				level = 90,
				league = "My Private Ruthless League",
			},
		}

		local ok, err = pcall(function()
			importTab:BuildCharacterList(nil)
		end)

		assert.True(ok, err)
		assert.are.equals(1, #importTab.controls.charSelect.list)
		assert.are.equals("PrivateLeagueCharacter", importTab.controls.charSelect.list[1].label)
		assert.True(importTab.controls.charSelect.list[1].detail:match("Amazon") ~= nil)
	end)

	it("falls back to the default class color for unknown character classes", function()
		local importTab = build.importTab
		importTab.lastCharList = {
			{
				name = "UnknownClassCharacter",
				class = "Future Ascendancy",
				level = 1,
				league = "My Private Ruthless League",
			},
		}

		local ok, err = pcall(function()
			importTab:BuildCharacterList(nil)
		end)

		assert.True(ok, err)
		assert.are.equals(1, #importTab.controls.charSelect.list)
		assert.True(importTab.controls.charSelect.list[1].detail:match("Future Ascendancy") ~= nil)
	end)

	it("imports ItemMod objects returned by the 3.29 API", function()
		local uniqueId = "api-3.29-item-mod-regression"
		build.importTab:ImportItem({
			inventoryId = "Ring",
			frameType = 2,
			name = "Regression Ring",
			typeLine = "Iron Ring",
			id = uniqueId,
			ilvl = 1,
			implicitMods = {
				{ description = "Adds 1 to 4 Physical Damage to Attacks" },
			},
			explicitMods = {
				{ description = "+10 to Strength", fractured = true },
				{ description = "+20 to Dexterity", crafted = true },
				{ description = "+30 to Intelligence", mutated = true },
			},
		}, "Ring 1")

		local importedItem
		for _, item in pairs(build.itemsTab.items) do
			if item.uniqueID == uniqueId then
				importedItem = item
				break
			end
		end

		assert.is_not_nil(importedItem)
		assert.are.equals("Adds 1 to 4 Physical Damage to Attacks", importedItem.implicitModLines[1].line)
		assert.are.equals("+10 to Strength", importedItem.explicitModLines[1].line)
		assert.True(importedItem.explicitModLines[1].fractured)
		assert.True(importedItem.explicitModLines[2].crafted)
		assert.True(importedItem.explicitModLines[3].mutated)
	end)
end)
