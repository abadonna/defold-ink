# defold-ink

The [Ink](https://www.inklestudios.com/ink/) language runtime implementation in Lua, an alternative to [Narrator](https://github.com/astrochili/narrator),  based on parsing [ink JSON](https://github.com/inkle/ink/blob/master/Documentation/ink_JSON_runtime_format.md) files. 

## Example
```lua
local ink = require "ink.story"

-- Parse a story from the JSON file. Make sure it's UTF8!
local res = sys.load_resource("/assets/test.json")
local story = ink.create(res)

-- Begin the story
local paragraphs, answers = story.continue()

-- Output text to the player
for _, p in ipairs (paragraphs) do
	pprint(p.text)
end

if #answers > 0 then
	for i, a in ipairs (answers) do
		pprint("[" .. i .. "] " .. a.text)
	end
end

 -- Send answer #1 to the story to generate new paragraphs
paragraphs, answers = story.continue(1)

```
### Defold
You can use defold-ink in your own project by adding it as a Defold library [dependency](http://www.defold.com/manuals/libraries/). Open your game.project file and in the dependencies field under project add:

```
https://github.com/abadonna/defold-ink/archive/master.zip

```

Then you can require the ```ink.story``` module.

## Documentation
### create(json)
Parses the Ink json string and returns a story instance. Make sure it's UTF8!
```lua
local ink = require "ink.story"
local res = sys.load_resource("/assets/test.json")
local story = ink.create(res)
```

### story.continue(answer_index)
Returns paragraphs and choices. Parameter "answer_index" is ignored if the story just begins.
```lua
local paragraphs, choices = story.continue(1)

```


### story.add_observer(var_name, f)
Assigns an observer function to the global variable. Each global variable can have multiple observers.


### story.remove_observer(var_name, f)
Removes an observer function.


### story.assign_value(name, value)
Assigns value to global variable and calls all it's observers.


### story.eval(expression)
Returns a result of evaluation of string expression, all names of global variables will be replaced by values.


### story.save()
Returns the current state of the story. Can be saved and used to restore story later.
```lua
local filename = sys.get_save_file("inktest", "story")
sys.save(filename, story.save())

```

### story.load(state)
Restores story from the saved state. Story should be created with the same - or at least similar :) - json.
Returns it's last paragraphs and choices.
```lua
local story = ink.create(json_string)
local paragraphs, choices = story.load(state)

```


### story.variables
Just a table of all global variables you can read and set. Use **story.assign_value(name, value)** to notify observer functions about the change.

---