const fs = require('fs');
const path = require('path');
const Pool = require('pg').Pool
const pool = new Pool({
  user: 'postgres',
  password: 'postgres',
  host: process.env.DB_HOSTNAME,
  database: 'users',
  port: 5432,
  ssl: {
    ca: [fs.readFileSync(path.resolve('./us-east-1-bundle.pem'), 'ascii')]
  },
})

const getUsers = (request, response) => {
  pool.query('SELECT * FROM users ORDER BY id ASC', (error, results) => {
    if (error) {
      throw error
    }
    response.status(200).json(results.rows)
  })
}

const createUser = (request, response) => {
  const { name, email } = request.body

  pool.query('INSERT INTO users (name, email) VALUES ($1, $2) RETURNING *', [name, email], (error, results) => {
    if (error) {
      throw error
    }
    response.status(201).send(`User added with ID: ${results.rows[0].id}`)
  })
}

module.exports = {
  getUsers,
  createUser,
}