--- KNOWN ISSUES:
-- - When scrolled down and toggling Ignored off, the display can get cut off not displaying all spells
-- - When ignoring things at the very bottom, it will shift around weird

local L = ClassTrainerPlusText;

CLASS_TRAINER_SKILLS_DISPLAYED = 11;
CLASS_TRAINER_SKILL_HEIGHT = 16;
MAX_LEARNABLE_PROFESSIONS = 2;

-- Trainer Filter Default Values
TRAINER_FILTER_AVAILABLE = 1;
TRAINER_FILTER_UNAVAILABLE = 1;
TRAINER_FILTER_USED = 0;
TRAINER_FILTER_IGNORED = 1;

ClassTrainerPlusDBPC = {};

local spellsToStripSubtextFrom = {
	[3127] = true, -- Parry, which is flagged Passive by GetSpellSubtext but not by GetTrainerServiceInfo
	[674] = true, -- Dual Wield, same as Parry
	[2836] = true, -- Detect Traps, passive
	[20608] = true -- Reincarnation, passive
};
local spellsToAllowRanklessMatch = {
	[921] = true, -- Pick Pocket, has Rank 1 in trainer ui, no rank from spell info
	[29166] = true, -- Innervate, has Rank 1 in trainer ui, no rank from spell info
};

local realSpellNameMap = {};
local abilities = {
	_store = {},
	_spellIds = {},
	_partialMatchSpells = {},
	GetByNameAndSubText = function(self, serviceName, serviceSubText)
		local key = self.getKey(serviceName, serviceSubText);
		if (self._store[key] == nil) then
			key = self.getAlternateKey(serviceName);
			if (self._store[key] ~= nil) then
				return self._store[key];
			end
		end
		if (realSpellNameMap[serviceName] and realSpellNameMap[serviceName][serviceSubText]) then
			key = self.getKey(realSpellNameMap[serviceName][serviceSubText], serviceSubText);
		end
		return self._store[key];
	end,
	IsIgnored = function(self, serviceName, serviceSubText)
		local ability = self:GetByNameAndSubText(serviceName, serviceSubText);
		return ability ~= nil and ability.isIgnored;
	end,
	getKey = function(serviceName, serviceSubText)
		local abilityKey = serviceName;
		if (serviceSubText ~= nil and serviceSubText ~= '') then
			abilityKey = abilityKey.." "..serviceSubText;
		end
		return abilityKey;
	end,
	getAlternateKey = function(serviceName) 
		return serviceName.." *";
	end,
	IsSpellIdStored = function(self, spellId)
		return self._spellIds[spellId] ~= nil;
	end,
	-- TODO: Refactor load and update
	Load = function(self, table)
		self._store = {};
		self._spellIds = {};
		for _, spellId in pairs(table) do
			local spell = Spell:CreateFromSpellID(spellId);
			spell:ContinueOnSpellLoad(function() 
				local spellName = spell:GetSpellName();
				local subText = spell:GetSpellSubtext();
				if (spellsToStripSubtextFrom[spellId]) then
					subText = "";
				end
				if (spellsToAllowRanklessMatch[spellId]) then
					subText = "*";
				end
				local key = self.getKey(spellName, subText);
				if (self._store[key] == nil) then
					self._store[key] = {
						spellId = spellId,
						isIgnored = false
					};
				end
				self._spellIds[spellId] = key;
				if (ClassTrainerFrame and ClassTrainerFrame:IsVisible()) then
					CTP_UpdateService();
					ClassTrainerFrame_Update();
				end
			end);
		end
	end,
	Update = function(self, table)
		for spellId, isIgnored in pairs(table) do
			local spell = Spell:CreateFromSpellID(spellId);
			spell:ContinueOnSpellLoad(function() 
				local spellName = spell:GetSpellName();
				local subText = spell:GetSpellSubtext();
				if (spellsToStripSubtextFrom[spellId]) then
					subText = "";
				end
				if (spellsToAllowRanklessMatch[spellId]) then
					subText = "*";
				end
				local key = self.getKey(spellName, subText);
				self._store[key] = {
					spellId = spellId,
					isIgnored = isIgnored
				};
			end);
		end
	end
};

local _, englishClass = UnitClass("player");
englishClass = string.gsub(string.lower(englishClass),"^%l", string.upper);
local classSpellIds = _G[format("ClassTrainerPlus%sSpellIds", englishClass)];
abilities:Load(classSpellIds);

local function UpdateUserFilters()
	abilities:Update(ClassTrainerPlusDBPC);
	CTP_UpdateService();
	if (ClassTrainerFrame and ClassTrainerFrame:IsVisible()) then
		ClassTrainerFrame_Update();
	end
end

StaticPopupDialogs["CONFIRM_PROFESSION"] = {
	preferredIndex = 3,
	text = format(PROFESSION_CONFIRMATION1, "XXX"),
	button1 = ACCEPT,
	button2 = CANCEL,
	OnAccept = function()
		BuyTrainerService(ClassTrainerFrame.selectedService);
		ClassTrainerFrame.showSkillDetails = nil;
		ClassTrainer_SetSelection(ClassTrainerFrame.selectedService);
		ClassTrainerFrame_Update();
	end,
	OnShow = function(self)
		local profCount = GetNumPrimaryProfessions();
		if ( profCount == 0 ) then
			_G[self:GetName().."Text"]:SetText(format(PROFESSION_CONFIRMATION1, GetTrainerServiceSkillLine(ClassTrainerFrame.selectedService)));
		else
			_G[self:GetName().."Text"]:SetText(format(PROFESSION_CONFIRMATION2, GetTrainerServiceSkillLine(ClassTrainerFrame.selectedService)));
		end
	end,
	showAlert = 1,
	timeout = 0,
	hideOnEscape = 1
};

local trainerServices = {
	totalServices = 0,
	visibleServices = 0,
	showIgnored = TRAINER_FILTER_IGNORED,
	allHeadersCollapsed = false,
	Update = function(self)
		self._byPosition = {};
		self._byServiceId = {};
		self.showIgnored = TRAINER_FILTER_IGNORED == 1;
		self.totalServices = GetNumTrainerServices();
		local currentSection = nil;
		local candidateSections = {};
		for i = 1, self.totalServices, 1 do
			local serviceName, serviceSubText, serviceType, isExpanded = GetTrainerServiceInfo(i);
			if (serviceType == "header") then
				currentSection = {
					name = serviceName,
					type = serviceType,
					subText = serviceSubText,
					isExpanded = isExpanded,
					serviceId = i,
					skills = {},
					isHidden = false
				};
				self._byServiceId[i] = currentSection;
				tinsert(candidateSections, currentSection);
			else 
				if (realSpellNameMap[serviceName] == nil) then
					realSpellNameMap[serviceName] = {};
				end
				if (serviceSubText and realSpellNameMap[serviceName][serviceSubText] == nil) then
					GameTooltip:SetTrainerService(i);
					local tooltipName = GameTooltipTextLeft1:GetText();
					if (tooltipName and string.find(tooltipName, serviceName, 1, true)) then
						realSpellNameMap[serviceName][serviceSubText] = tooltipName;
					end
				end
				local isIgnored = abilities:IsIgnored(serviceName, serviceSubText);
				local ability =  {
					serviceId = i,
					name = serviceName,
					subText = serviceSubText,
					isIgnored = isIgnored,
					type = serviceType,
					isHidden = false
				};
				if (serviceSubText ~= nil and serviceSubText ~= "") then
					ability.menuTitle = serviceName.." "..format(PARENS_TEMPLATE, serviceSubText);
				else
					ability.menuTitle = serviceName;
				end
				self._byServiceId[i] = ability;
				if (not isIgnored or self.showIgnored) then
					tinsert(currentSection.skills, ability);
				end
				if (isIgnored and serviceType ~= "used") then
					if (not self.showIgnored) then
						ability.isHidden = true;
					end
				end
			end
		end
		self.visibleServices = 0;
		local numHeaders = #candidateSections;
		local numNotExpanded = 0;
		for _, candidate in ipairs(candidateSections) do
			local skillsInCandidate = #candidate.skills
			if (self.showIgnored or skillsInCandidate > 0 or not candidate.isExpanded) then
				self.visibleServices = self.visibleServices + 1;
				self._byPosition[self.visibleServices] = candidate;
				for j = 1, #candidate.skills, 1 do
					self.visibleServices = self.visibleServices + 1;
					self._byPosition[self.visibleServices] = candidate.skills[j];
				end
			else
				candidate.isHidden = true;
			end
			if (not candidate.isExpanded and not candidate.isHidden) then
				numNotExpanded = numNotExpanded + 1;
			end
		end
		self.allHeadersCollapsed = numHeaders == numNotExpanded;
	end,
	IsSelected = function(self, serviceId)
		if (not serviceId or serviceId == 0) then return false; end;
		local service = self._byServiceId[serviceId];
		return (service and not service.isHidden) and GetTrainerSelectionIndex() == serviceId;
	end,
	GetFirstVisibleNonHeaderService = function(self)
		for _, service in ipairs(self._byPosition) do
			if (service.type ~= "header") then
				return service;
			end
		end
	end,
	GetNextAvailableServiceId = function(self, serviceId)
		for id, service in ipairs(self._byPosition) do
			if (service.serviceId == serviceId and id < #self._byPosition) then
				local nextService = self._byPosition[id+1];
				if (nextService.type == "available") then
					return nextService.serviceId;
				else
					serviceId = nextService.serviceId;
				end
			end
		end
	end,
	GetServiceAtPosition = function(self, position)
		return self._byPosition[position];
	end,
	GetService = function(self, id)
		return self._byServiceId[id];
	end
};
function CTP_UpdateService()
	trainerServices:Update();
end

function ClassTrainerFrame_Show()
	ShowUIPanel(ClassTrainerFrame);
	if ( not ClassTrainerFrame:IsVisible() ) then
		CloseTrainer();
		return;
	end
	
	ClassTrainerTrainButton:Disable();
	--Reset scrollbar
	ClassTrainerListScrollFrameScrollBar:SetMinMaxValues(0, 0); 
	ClassTrainerListScrollFrameScrollBar:SetValue(0);

	ClassTrainer_SelectFirstLearnableSkill();

	trainerServices:Update();
	ClassTrainerFrame_Update();
	UpdateMicroButtons();
end

function ClassTrainerFrame_Hide()
	HideUIPanel(ClassTrainerFrame);
end

function ClassTrainerFrame_OnLoad(self)
	self:RegisterEvent("TRAINER_UPDATE");
	self:RegisterEvent("TRAINER_DESCRIPTION_UPDATE");
	self:RegisterEvent("TRAINER_SERVICE_INFO_NAME_UPDATE");
	self:RegisterEvent("ADDON_LOADED");
	ClassTrainerDetailScrollFrame.scrollBarHideable = 1;
	-- Set each skill button to handle right clicks
	for i=1,CLASS_TRAINER_SKILLS_DISPLAYED,1 do
		local skillButton = _G["ClassTrainerSkill"..i];
		skillButton:RegisterForClicks("LeftButtonUp", "RightButtonUp");
	end
end

local function TrainerUpdateHandler()
	trainerServices:Update();

	local selectedIndex = GetTrainerSelectionIndex();
	if ( selectedIndex > 1 ) then
		-- Select the first available ability
		local service = trainerServices:GetService(selectedIndex);
        if ( selectedIndex > trainerServices.totalServices ) then
            FauxScrollFrame_SetOffset(ClassTrainerListScrollFrame, 0);
			ClassTrainerListScrollFrameScrollBar:SetValue(0);
			local firstAbility = trainerServices:GetFirstVisibleNonHeaderService();
			if (firstAbility == nil) then
				selectedIndex = nil;
			else
				selectedIndex = firstAbility.serviceId;
			end
		elseif (service and service.isHidden) then
			while (service and (service.isHidden or service.type == "header")) do
				selectedIndex = selectedIndex + 1;
				service = trainerServices:GetService(selectedIndex);
			end
			if (selectedIndex > trainerServices.totalServices) then
				selectedIndex = nil;
			end
		end
        ClassTrainer_SetSelection(selectedIndex);
    else
        ClassTrainer_SelectFirstLearnableSkill();
    end
    ClassTrainerFrame_Update();
end

function ClassTrainerFrame_OnEvent(self, event, ...)
	if ( event == "ADDON_LOADED" and ... == "ClassTrainerPlus" ) then
		SetTrainerServiceTypeFilter("available", TRAINER_FILTER_AVAILABLE);
		SetTrainerServiceTypeFilter("unavailable", TRAINER_FILTER_UNAVAILABLE);
		SetTrainerServiceTypeFilter("used", TRAINER_FILTER_USED);
		ClassTrainerPlusDBPC = ClassTrainerPlusDBPC or {};
		UpdateUserFilters();
	end
	if ( not self:IsVisible() ) then
		return;
	end
	if ( event == "TRAINER_UPDATE" ) then
		TrainerUpdateHandler();
	elseif ( event == "TRAINER_DESCRIPTION_UPDATE" ) then
		ClassTrainer_SetSelection(GetTrainerSelectionIndex());
	elseif ( event == "TRAINER_SERVICE_INFO_NAME_UPDATE" ) then
		-- It would be really cool if I could uniquely identify the button associated
		-- with a particular spell here, and only update the name on that button.
		TrainerUpdateHandler();
	end
end

function ClassTrainerFrame_Update()
	SetPortraitTexture(ClassTrainerFramePortrait, "npc");
	ClassTrainerNameText:SetText(UnitName("npc"));
	ClassTrainerGreetingText:SetText(GetTrainerGreetingText());
	local numTrainerServices = trainerServices.totalServices;
	local numFilteredTrainerServices = trainerServices.visibleServices;
    local skillOffset = FauxScrollFrame_GetOffset(ClassTrainerListScrollFrame);
	local showIgnored = TRAINER_FILTER_IGNORED == 1

	-- If no spells then clear everything out
	if ( numFilteredTrainerServices == 0 ) then
		ClassTrainerCollapseAllButton:Disable();
		ClassTrainerFrame.selectedService = nil;
	else
		ClassTrainerCollapseAllButton:Enable();
	end

	-- If selectedService is nil hide everything
	if ( not ClassTrainerFrame.selectedService ) then
		ClassTrainer_HideSkillDetails();
		ClassTrainerTrainButton:Disable();
	end

	-- Change the setup depending on if its a class trainer or tradeskill trainer
	if ( IsTradeskillTrainer() ) then
		ClassTrainer_SetToTradeSkillTrainer();
	else
		ClassTrainer_SetToClassTrainer();
	end

	-- ScrollFrame update
	FauxScrollFrame_Update(ClassTrainerListScrollFrame, numFilteredTrainerServices, CLASS_TRAINER_SKILLS_DISPLAYED, CLASS_TRAINER_SKILL_HEIGHT, nil, nil, nil, ClassTrainerSkillHighlightFrame, 293, 316 )
	
	--ClassTrainerUsedButton:Show();
	ClassTrainerMoneyFrame:Show();
	
	ClassTrainerSkillHighlightFrame:Hide();
	-- Fill in the skill buttons
    for i=1, CLASS_TRAINER_SKILLS_DISPLAYED, 1 do
		local skillIndex = i + skillOffset;
		local skillButton = _G["ClassTrainerSkill"..i]; 
		local serviceName, serviceSubText, serviceType, isExpanded;
		local moneyCost;

		if ( skillIndex <= numFilteredTrainerServices ) then	
			local service = trainerServices:GetServiceAtPosition(skillIndex);
			serviceName = service.name;
			serviceSubText = service.subText;
			serviceType = service.type;
			isExpanded = service.isExpanded;
			if ( not serviceName ) then
				serviceName = UNKNOWN;
			end
			
			-- Set button widths if scrollbar is shown or hidden
			if ( ClassTrainerListScrollFrame:IsVisible() ) then
				skillButton:SetWidth(293);
			else
				skillButton:SetWidth(323);
			end
			local skillSubText = _G["ClassTrainerSkill"..i.."SubText"];
			-- Type stuff
			if ( serviceType == "header" ) then
				local skillText = _G["ClassTrainerSkill"..i.."Text"];
				skillText:SetText(serviceName);
				skillButton:SetNormalFontObject("GameFontNormal");

				skillSubText:Hide();
				if ( isExpanded ) then
					skillButton:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up");
				else
					skillButton:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up");
				end
				_G["ClassTrainerSkill"..i.."Highlight"]:SetTexture("Interface\\Buttons\\UI-PlusButton-Hilight");
			else
				skillButton:SetNormalTexture("");
				_G["ClassTrainerSkill"..i.."Highlight"]:SetTexture("");
				local skillText = _G["ClassTrainerSkill"..i.."Text"];
				skillText:SetText("  "..serviceName);
				if ( serviceSubText and serviceSubText ~= "" ) then
					skillSubText:SetText(format(PARENS_TEMPLATE, serviceSubText));
					skillSubText:SetPoint("LEFT", "ClassTrainerSkill"..i.."Text", "RIGHT", 10, 0);
					skillSubText:Show();
				else
					skillSubText:Hide();
				end
				
				-- Cost Stuff
				moneyCost, _ = GetTrainerServiceCost(skillIndex);
                if ( serviceType == "available" ) then
                    if (not service.isIgnored) then
					    skillButton:SetNormalFontObject("GameFontNormalLeftGreen");
					    ClassTrainer_SetSubTextColor(skillButton, 0, 0.6, 0);
					else
						skillButton:SetNormalFontObject("ClassTrainerPlusIgnoredFont");
					    ClassTrainer_SetSubTextColor(skillButton, 0.6, 0.6, 0.1);
                    end
				elseif ( serviceType == "used" ) then
					skillButton:SetNormalFontObject("GameFontDisable");
					ClassTrainer_SetSubTextColor(skillButton, 0.5, 0.5, 0.5);
				else
					if (service.isIgnored) then
						skillButton:SetText(skillButton:GetText().." |cFFffffa3*|r");	
					end
					skillButton:SetNormalFontObject("GameFontNormalLeftRed");
					ClassTrainer_SetSubTextColor(skillButton, 0.6, 0, 0);
				end		
			end
			skillButton:SetID(service.serviceId);
			skillButton:Show();
			-- Place the highlight and lock the highlight state
			if (trainerServices:IsSelected(service.serviceId)) then
				ClassTrainerSkillHighlightFrame:SetPoint("TOPLEFT", "ClassTrainerSkill"..i, "TOPLEFT", 0, 0);
				ClassTrainerSkillHighlightFrame:Show();
				skillButton:LockHighlight();
				ClassTrainer_SetSubTextColor(skillButton, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b);
				if ( moneyCost and moneyCost > 0 ) then
					ClassTrainerCostLabel:Show();
				end
			else
				skillButton:UnlockHighlight();
			end
		else
			skillButton:Hide();
		end
	end

	-- Show skill details if the skill is visible
	if (trainerServices:IsSelected(ClassTrainerFrame.selectedService)) then
		ClassTrainer_ShowSkillDetails();
	else	
		ClassTrainer_HideSkillDetails();
	end
	-- Set the expand/collapse all button texture
	if (trainerServices.allHeadersCollapsed) then
		ClassTrainerCollapseAllButton.collapsed = 1;
		ClassTrainerCollapseAllButton:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up");
	else
		ClassTrainerCollapseAllButton.collapsed = nil;
		ClassTrainerCollapseAllButton:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up");
	end
end

function ClassTrainer_SelectFirstLearnableSkill()
	if ( trainerServices.visibleServices > 0 ) then
		ClassTrainerFrame.showSkillDetails = 1;
		local firstAbility = trainerServices:GetFirstVisibleNonHeaderService();
		if (firstAbility ~= nil) then
			ClassTrainer_SetSelection(firstAbility.serviceId)
		else
			ClassTrainerFrame.showSkillDetails = nil;
			ClassTrainerFrame.selectedService = nil;
			ClassTrainer_SetSelection();
		end
		
		FauxScrollFrame_SetOffset(ClassTrainerListScrollFrame, 0)		
	else
		ClassTrainerFrame.showSkillDetails = nil;
		ClassTrainerFrame.selectedService = nil;
		ClassTrainer_SetSelection();
	end
	ClassTrainerListScrollFrame:SetVerticalScroll(0);
end

function ClassTrainer_SetSelection(id)
	-- General Info
	if ( not id ) then
		ClassTrainer_HideSkillDetails();
		ClassTrainerTrainButton:Disable();
		return;
	end
	
	local showIgnored = TRAINER_FILTER_IGNORED == 1;
	local serviceName, serviceSubText, serviceType, isExpanded;
	local service = trainerServices:GetService(id);
	serviceName = service.name;
	serviceSubText = service.subText;
	serviceType = service.type;
	isExpanded = service.isExpanded;

	ClassTrainerSkillHighlightFrame:Show();
	
    if ( serviceType == "available" ) then
        if (not service.isIgnored) then
            ClassTrainerSkillHighlight:SetVertexColor(0, 1.0, 0);
        else
            ClassTrainerSkillHighlight:SetVertexColor(1.0, 1.0, 0.6);
        end
	elseif ( serviceType == "used" ) then
		ClassTrainerSkillHighlight:SetVertexColor(0.5, 0.5, 0.5);
	elseif ( serviceType == "unavailable" ) then
		ClassTrainerSkillHighlight:SetVertexColor(0.9, 0, 0);
	else
		-- Is header, so collapse or expand header
		ClassTrainerSkillHighlightFrame:Hide();

		if ( isExpanded ) then
			CollapseTrainerSkillLine(id);
		else
			ExpandTrainerSkillLine(id);
		end
		return;
	end
	if ( ClassTrainerFrame.showSkillDetails ) then
		ClassTrainer_ShowSkillDetails();
	else
		ClassTrainer_HideSkillDetails();
		--ClassTrainerTrainButton:Disable();
		return;
	end

	if ( not serviceName ) then
		serviceName = UNKNOWN;
	end
	ClassTrainerSkillName:SetText(serviceName);
	if ( not serviceSubText ) then
		serviceSubText = "";
	end
	ClassTrainerSubSkillName:SetText(PARENS_TEMPLATE:format(serviceSubText));
	ClassTrainerFrame.selectedService = id;
	SelectTrainerService(id);
	ClassTrainerSkillIcon:SetNormalTexture(GetTrainerServiceIcon(id));
	-- Build up the requirements string
	local requirements = "";
	-- Level Requirements
	local reqLevel = GetTrainerServiceLevelReq(id);
	local separator = "";
	if ( reqLevel > 1 ) then
		separator = ", ";
		local _, isPetLearnSpell = IsTrainerServiceLearnSpell(id);
		if ( isPetLearnSpell ) then
			if ( UnitLevel("pet") >= reqLevel ) then
				requirements = requirements..format(TRAINER_PET_LEVEL, reqLevel);
			else
				requirements = requirements..format(TRAINER_PET_LEVEL_RED, reqLevel);
			end
		else
			if ( UnitLevel("player") >= reqLevel ) then
				requirements = requirements..format(TRAINER_REQ_LEVEL, reqLevel);
			else
				requirements = requirements..format(TRAINER_REQ_LEVEL_RED, reqLevel);
			end
		end
	end
	-- Skill Requirements
	local skill, rank, hasReq = GetTrainerServiceSkillReq(id);
	if ( skill ) then
		if ( hasReq ) then
			requirements = requirements..separator..format(TRAINER_REQ_SKILL_RANK, skill, rank );
		else
			requirements = requirements..separator..format(TRAINER_REQ_SKILL_RANK_RED, skill, rank );
		end
		separator = ", ";
	end
	-- Ability Requirements
	local numRequirements = GetTrainerServiceNumAbilityReq(id);
	local ability, abilityName, abilitySubText, abilityType;
	if ( numRequirements > 0 ) then
		for i=1, numRequirements, 1 do
			ability, hasReq = GetTrainerServiceAbilityReq(id, i);
			abilityName, abilitySubText, abilityType = GetTrainerServiceInfo(id);
			if (ability) then
				if ( hasReq or (abilityType == "used") ) then
					requirements = requirements..separator..format(TRAINER_REQ_ABILITY, ability );
				else
					requirements = requirements..separator..format(TRAINER_REQ_ABILITY_RED, ability );
				end
			end
			separator = ", ";
		end
	end
	if ( requirements ~= "" ) then
		ClassTrainerSkillRequirements:SetText(REQUIRES_LABEL.." "..requirements);
	else
		ClassTrainerSkillRequirements:SetText("");
	end
	-- Money Frame and cost
	local moneyCost, isProfession = GetTrainerServiceCost(id);
	local cp1, cp2 = UnitCharacterPoints("player");
	local unavailable, skillPointCost;
	if ( moneyCost == 0 ) then
		ClassTrainerDetailMoneyFrame:Hide();
		ClassTrainerCostLabel:Hide();
		ClassTrainerSkillDescription:SetPoint("TOPLEFT", "ClassTrainerCostLabel", "TOPLEFT", 0, 0);
	else
		ClassTrainerDetailMoneyFrame:Show();
		ClassTrainerCostLabel:Show();
		ClassTrainerSkillDescription:SetPoint("TOPLEFT", "ClassTrainerCostLabel", "BOTTOMLEFT", 0, -10);
		if ( GetMoney() >= moneyCost ) then
			SetMoneyFrameColor("ClassTrainerDetailMoneyFrame", "white");
		else
			SetMoneyFrameColor("ClassTrainerDetailMoneyFrame", "red");
			unavailable = 1;
		end
	end
	
	MoneyFrame_Update("ClassTrainerDetailMoneyFrame", moneyCost);
	if (isProfession) then
		ClassTrainerFrame.showDialog = true;
		local profCount = GetNumPrimaryProfessions();
		if profCount >= 2 then
			unavailable = 1;
		end
	else
		ClassTrainerFrame.showDialog = nil;
	end
	if (not showIgnored and service.isIgnored) then
		unavailable = 1;
	end

	ClassTrainerSkillDescription:SetText( GetTrainerServiceDescription(id) );
	if ( serviceType == "available" and not unavailable ) then
		ClassTrainerTrainButton:Enable();
	else
		ClassTrainerTrainButton:Disable();
	end

	-- Determine what type of spell to display
	local isLearnSpell;
	local isPetLearnSpell;
	isLearnSpell, isPetLearnSpell = IsTrainerServiceLearnSpell(id);
	if ( isLearnSpell ) then
		if ( isPetLearnSpell ) then
			ClassTrainerSkillName:SetText(ClassTrainerSkillName:GetText() ..TRAINER_PET_SPELL_LABEL);
		end
	end
	ClassTrainerDetailScrollFrame:UpdateScrollChildRect();

	-- Close the confirmation dialog if you choose a different skill
	if ( StaticPopup_Visible("CONFIRM_PROFESSION") ) then
		StaticPopup_Hide("CONFIRM_PROFESSION");
	end
end

function ClassTrainerSkillButton_OnClick(self, button)
	if (ClassTrainerPlusToggleFrame ~= nil and ClassTrainerPlusToggleFrame:IsVisible()) then
		CloseDropDownMenus();
	end
	
	if ( button == "LeftButton" ) then
		local service = trainerServices:GetService(self:GetID());
		ClassTrainerFrame.selectedService = service.serviceId;
		ClassTrainerFrame.showSkillDetails = 1;
		ClassTrainer_SetSelection(self:GetID());
		ClassTrainerFrame_Update();
	elseif (button == "RightButton" and not IsTradeskillTrainer()) then
		local service = trainerServices:GetService(self:GetID());
		if (service.type == "header" or service.type == "used") then
			return;
		end
		PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON);
		local menuTitle = service.menuTitle;
		local checked = false;
		if (service.isIgnored) then
			checked = true;
		end
		local menu = {
			{text = menuTitle, isTitle = true,classicChecks=true},
			{
				text = L["IGNORED"], 
				checked = checked,
				func = function() 
					PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON);
					local ability = abilities:GetByNameAndSubText(service.name, service.subText);
					local spellId = ability.spellId;
					if (spellId ~= nil and spellId > 0) then
						if (ClassTrainerPlusDBPC[spellId] == nil) then
							ClassTrainerPlusDBPC[spellId] = checked;
						end
						ClassTrainerPlusDBPC[spellId] = not ClassTrainerPlusDBPC[spellId];
					else 
						print(format("CTP: could not find spell for %s", service.name));
					end
					UpdateUserFilters();
					TrainerUpdateHandler();
				end, 
				classicChecks = true
			}
		};
		local menuFrame = CreateFrame("Frame", "ClassTrainerPlusToggleFrame", UIParent, "UIDropDownMenuTemplate");
		EasyMenu(menu, menuFrame, "cursor", 10, 35, "MENU");
	end
end

function ClassTrainerTrainButton_OnClick()
	if (IsTradeskillTrainer() and ClassTrainerFrame.showDialog) then
		StaticPopup_Show("CONFIRM_PROFESSION");
	else
		local service = trainerServices:GetService(ClassTrainerFrame.selectedService);
		BuyTrainerService(ClassTrainerFrame.selectedService);
		local nextSelection = trainerServices:GetNextAvailableServiceId(ClassTrainerFrame.selectedService);

		if (nextSelection ~= nil and nextSelection <= trainerServices.totalServices) then
			ClassTrainerFrame.showSkillDetails = 1;
			ClassTrainer_SetSelection(nextSelection);
		else
			ClassTrainerFrame.showSkillDetails = nil;
			ClassTrainerFrame.selectedService = nil;
		end

		ClassTrainerFrame_Update();
	end
end

function ClassTrainer_SetSubTextColor(button, r, g, b)
	button.subR = r;
	button.subG = g;
	button.subB = b;
	_G[button:GetName().."SubText"]:SetTextColor(r, g, b);
end

function ClassTrainerCollapseAllButton_OnClick(self)
	if (self.collapsed) then
		self.collapsed = nil;
		ExpandTrainerSkillLine(0);
	else
		self.collapsed = 1;
		ClassTrainerListScrollFrameScrollBar:SetValue(0);
		CollapseTrainerSkillLine(0);
	end
end

function ClassTrainer_HideSkillDetails()
	ClassTrainerSkillName:Hide();
	ClassTrainerSkillIcon:Hide();
	ClassTrainerSkillRequirements:Hide();
	ClassTrainerSkillDescription:Hide();
	ClassTrainerDetailMoneyFrame:Hide();
	ClassTrainerCostLabel:Hide();
end

function ClassTrainer_ShowSkillDetails()
	ClassTrainerSkillName:Show();
	ClassTrainerSkillIcon:Show();
	ClassTrainerSkillRequirements:Show();
	ClassTrainerSkillDescription:Show();
	ClassTrainerDetailMoneyFrame:Show();
	--ClassTrainerCostLabel:Show();
end

function ClassTrainer_SetToTradeSkillTrainer()
	CLASS_TRAINER_SKILLS_DISPLAYED = 10;
	ClassTrainerSkill11:Hide();
	ClassTrainerListScrollFrame:SetHeight(168);
	ClassTrainerDetailScrollFrame:SetHeight(135);
	local cp1, cp2 = UnitCharacterPoints("player");
	ClassTrainerHorizontalBarLeft:SetPoint("TOPLEFT", "ClassTrainerFrame", "TOPLEFT", 15, -259);
end

function ClassTrainer_SetToClassTrainer()
	CLASS_TRAINER_SKILLS_DISPLAYED = 11;
	ClassTrainerListScrollFrame:SetHeight(184);
	ClassTrainerDetailScrollFrame:SetHeight(119);
	ClassTrainerHorizontalBarLeft:SetPoint("TOPLEFT", "ClassTrainerFrame", "TOPLEFT", 15, -275);
end

-- Dropdown functions
function ClassTrainerFrameFilterDropDown_OnLoad(self)
	UIDropDownMenu_Initialize(self, ClassTrainerFrameFilterDropDown_Initialize);
	UIDropDownMenu_SetText(self, FILTER);
	UIDropDownMenu_SetWidth(self, 130);
end

function ClassTrainerFrameFilterDropDown_Initialize()
	-- Available button
	local info = {};
	local checked = nil;
	if ( GetTrainerServiceTypeFilter("available") ) then
		checked = 1;
	end
	info.text = GREEN_FONT_COLOR_CODE..AVAILABLE..FONT_COLOR_CODE_CLOSE;
	info.value = "available";
	info.func = ClassTrainerFrameFilterDropDown_OnClick;
	info.checked = checked;
	info.keepShownOnClick = 1;
	info.classicChecks = true;
    UIDropDownMenu_AddButton(info);
	
	if (not IsTradeskillTrainer()) then
		-- Ignored button
		info = {};
		checked = nil;
		if (TRAINER_FILTER_IGNORED == 1) then
			checked = 1;
		end
		info.text = LIGHTYELLOW_FONT_COLOR_CODE..L["IGNORED"]..FONT_COLOR_CODE_CLOSE;
		info.value = "ignored";
		info.func = ClassTrainerFrameFilterDropDown_OnClick;
		info.checked = checked;
		info.keepShownOnClick = 1;
		info.classicChecks = true;
		UIDropDownMenu_AddButton(info);
	end

	-- Unavailable button
	info = {};
	checked = nil;
	if ( GetTrainerServiceTypeFilter("unavailable") ) then
		checked = 1;
	end
	info.text = RED_FONT_COLOR_CODE..UNAVAILABLE..FONT_COLOR_CODE_CLOSE;
	info.value = "unavailable";
	info.func = ClassTrainerFrameFilterDropDown_OnClick;
	info.checked = checked;
	info.keepShownOnClick = 1;
	info.classicChecks = true;
	UIDropDownMenu_AddButton(info);

	-- Already Known button
	info = {};
	checked = nil;
	if ( GetTrainerServiceTypeFilter("used") ) then
		checked = 1;
	end
	info.text = GRAY_FONT_COLOR_CODE..USED..FONT_COLOR_CODE_CLOSE;
	info.value = "used";
	info.func = ClassTrainerFrameFilterDropDown_OnClick;
	info.checked = checked;
	info.keepShownOnClick = 1;
	info.classicChecks = true;
	UIDropDownMenu_AddButton(info);
end

function ClassTrainerFrameFilterDropDown_OnClick(self)	
    local newFilterValue = 0;
	if (UIDropDownMenuButton_GetChecked(self)) then
		newFilterValue = 1;
    end
    
    _G["TRAINER_FILTER_"..strupper(self.value)] = newFilterValue;
	if (self.value == "ignored") then
        TrainerUpdateHandler();
    else
        SetTrainerServiceTypeFilter(self.value, newFilterValue);
    end
    
    ClassTrainerListScrollFrameScrollBar:SetValue(0);
end

local function trim(str)
	return (string.gsub(str, "^%s*(.-)%s*$", "%1"))
end

SLASH_CTP1 = "/ctp";
SLASH_CTP2 = "/classtrainerplus";
SlashCmdList["CTP"] = function (msg)
	local _, _, cmd, args = string.find(msg, "%s?(%w+)%s?(.*)")
	cmd = trim(string.lower(cmd));
	args = trim(string.lower(args));
	if (cmd == "sa") then
		CTP_ShowAll();
	end
	if (cmd == "import" and args == "") then
		print("You must include the import string when importing");
		return;
	elseif (cmd == "import") then
		local import = {};

		if (strlen(args) % 3 ~= 0) then
			print("ClassTrainerPlus could not import due to a malformed input string");
			return;
		end
		for i = 1, strlen(args), 3 do
			local part = string.sub(args, i, i+2);
			if (strlen(part) ~= 3) then
				print(format("ClassTrainerPlus ran into a malformed part, '%s', and aborted the import", part));
				return;
			end
			local spellId = tonumber(part, 36);
			if (not abilities:IsSpellIdStored(spellId)) then
				print(format("ClassTrainerPlus is aborting the import because spellId %d does not belong to this class", spellId));
				return;
			end
			tinsert(import, spellId);
		end
		local newImports = 0;
		for _, v in ipairs(import) do
			if (ClassTrainerPlusDBPC[v] ~= true) then
				ClassTrainerPlusDBPC[v] = true;
				newImports = newImports + 1;
			end
		end
		UpdateUserFilters();
		TrainerUpdateHandler();
		print(format("ClassTrainerPlus imported %d new ignored abilities (%d were already ignored)", newImports, #import-newImports));
	elseif (cmd == "clear") then
		ClassTrainerPlusDBPC = {};
		abilities:Load(classSpellIds);
		TrainerUpdateHandler();
		print("ClassTrainerPlus database cleared");
	end
end
