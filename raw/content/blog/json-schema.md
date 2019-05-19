+++
date = "2019-05-19T16:20:00+01:00"
title = "JSON Schema"
tags = ["go", "server", "http"]
categories = ["programming"]
draft = false
description = "JSON Schema + Go + APIs"
weight = 10
+++

## JSON Schema + Go + APIs

After working on a few Go HTTP servers i've noticed 
a few different patterns for API validations. I'm going to attempt to show off _yet another_ 
way this can be done and hopefully convince you to try out [JSON Schema](https://json-schema.org/).

### What is JSON Schema?
If you haven't heard of JSON Schema before, it's an attempt to apply structure to otherwise unstructured JSON.
As developers, sometimes "unstructured" JSON is incredibly convenient (looking at you [postgres](https://www.postgresql.org/docs/9.4/datatype-json.html)), 
but at some point in the lifecycle of that data, you will need to perform some validation on it. Whether that is checking if a certain field is present, the type of that field, if it's an integer between 1 and 10 exclusive, or something else.
This is where JSON Schema comes in.

### What can I do with JSON Schema?
Just about any data validations on each individual field. For example, you can validate:
* a field is an integer
* that integer is in the range [1-10)
* that field is present because it is _required_
* a field called "email" matches an email validation _regex_
* a field is a valid enum type

and much more (seriously, validate _[all the things](http://json-schema.org/latest/json-schema-validation.html#rfc.section.6))_.

### How can I have some?
Now that i've convinced you it's worth learning more about, let's dive into how we can add JSON Schema to a Go project.

One great feature of JSON Schema is that you can add validation to an existing project that using some implicit (or explicit) schema with no changes required. 

I'll be using [gojsonschema](https://github.com/xeipuuv/gojsonschema) to help with manipulating our schema and validating our JSON.

#### The Schema
The first thing you need to do in either a new project or an existing one is create your schema.

Let's say we're building a blogging website. The API we're building allows the frontend to `POST` blog posts via HTTP.

In our blog website, we accept 7 `POST` parameters (or, in JSON Schema, `properties`), and some of them have validations. Our schema looks like:

```json
{
  "$schema": "http://json-schema.org/draft-04/schema#",
  "type": "object",
  "title": "post",
  "description": "a blog post",
  "properties": {
    "title": {
      "type": "string",
      "minLength": 1,
      "maxLength": 50,
      "pattern": "^[A-Z].*"
    },
    "date": {
      "type": "string"
    },
    "body": {
      "type": "string"
    },
    "views": {
      "type": "integer",
      "minimum": 1
    },
    "post_type": {
      "type": "string",
      "enum": ["cross-post", "original"]
    },
    "tags": {
      "type": "array",
      "items": {
        "type": "string"
      }
    }
  },
  "required": ["title", "date", "body", "post_type"]
}
```

In our schema, we define 4 of these properties to be required, and we apply validations to all of them - some more strict than others.

For example, I want to make sure the `title` field starts with a capital letter, and the number of views of this post obviously can't go below `1`.

This is clearly a contrived example, but you can probably see how useful this would be to enforce at the API layer in your application 
and in a standard way for all your APIs. Add a new field to the API? Add _some_ validation so you can enforce that 
your application can handle whatever the client throws at you.

#### Loading our Schema

Now that we have written out our schema, we need to load our schema so we can use it to verify the `POST` body on every request.

I've chosen to check my schema into my project as a go string literal, but there are other ways to do this as well (gojsonschema [supports a static file on disk, Web/HTTP references, or custom Go types](https://github.com/xeipuuv/gojsonschema#loaders)).

I can then load my schema with:

```go
func loadSchema() (*gojsonschema.Schema, error) {
	loader := gojsonschema.NewStringLoader(schemaJSON)
	schema, err := gojsonschema.NewSchema(loader)
	if err != nil {
		return nil, err
	}

	return schema, nil
}
```

#### Decorate a Handler
I tend to decorate my `http.Handler`s with middleware so I can use do this schema validation in a single place.
I wrote an `http.Handler` that looks like this:

```go
func validate(schema *gojsonschema.Schema, next http.HandlerFunc) http.HandlerFuc {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, err := ioutil.ReadAll(r.Body)
		defer r.Body.Close()

		if err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}

		requestJSON := gojsonschema.NewBytesLoader(body)
		result, err := schema.Validate(requestJSON)

		if err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}

		if !result.Valid() {
			if err := writeError(result.Errors(), w); err != nil {
				w.WriteHeader(http.StatusInternalServerError)
				return
			}
		}

		next.ServeHTTP(w, r)
	})
}
```

I won't go into too much detail about the closure, but if you are interested in learning more about writing HTTP servers + go, I highly recommend [this](https://medium.com/statuscode/how-i-write-go-http-services-after-seven-years-37c208122831) blog post from Mat Ryer.

This is where all the validation comes into play - with my loaded `schema` from the step before, 
we can simple do a `schema.Validate(requestJSON)`, and pass in a `JSONLoader`. 
If the JSON body is invalid, we will see `result.Valid()` is `false` and we can check each
of the errors in `result.Errors()`.

#### Wire everything up

I have another handler to actually perform the request logic that looks like this:

```go
func process(w http.ResponseWriter, _ *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("valid request"))
}
```

In the `main` function, all we need is to decorate our `http.Handler` and begin our `http.Server`:


And voila - just like that, we have a middleware that will validate JSON payloads based
on a provided JSON Schema document. For each handler we want to register, we just need to 
provide the schema and all errors in validation will be caught in a consistent approach.

```go
handler := validate(schema, process)
http.ListenAndServe(":8000", handler)
```

#### Conclusion

JSON Schema is simple to use but quite powerful. It allows us to enforce the data transferred to/from APIs in a 
generic way that is self documenting and can be easily adding on to any existing project.

I hope i've convinced you to try JSON Schema in your next project that uses JSON. 

You can check out the full source code [here](https://github.com/mitchfriedman/schema-validations).

If you have thoughts or disagree with some things I've said here, reach out to me on [twitter](https://twitter.com/mitchfriedman5).

