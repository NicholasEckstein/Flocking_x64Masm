#include "SFML\Graphics.hpp"
#include <iostream>

struct Vec
{
	float x;
	float y;
};

struct Boid
{
	Vec position;
	Vec velocity;
	float rotation;

	Vec	averagePosition;
	Vec	averageVelocity;
	float neighborCount;
};

sf::RenderWindow* window = new sf::RenderWindow(sf::VideoMode(800, 600), "Flocking Demo", sf::Style::Close);
const int maxBoids = 1000;
sf::RectangleShape* boidShapes[maxBoids];
int boidCount = 0;
sf::Texture* boidTexture;

extern "C" void AsmInit(float windowWidth, float windowHeight, float boidWidth);
extern "C" void AsmUpdate(float deltaTime, float mouseX, float mouseY, int mouseDown);

//couldn't figure out how to do atan2 in assembly
extern "C" float Atan2(float y, float x) { return atan2(y, x); }

extern "C" void SetBoidData(Boid* boid, int index, int newCount)
{
	boidCount = newCount;
	boidShapes[index] = new sf::RectangleShape();
	boidShapes[index]->setTexture(boidTexture);
	sf::Vector2f size = sf::Vector2f(boidTexture->getSize());
	boidShapes[index]->setSize(size);
	boidShapes[index]->setOrigin(size * 0.5f);

	boidShapes[index]->setPosition(sf::Vector2f(boid->position.x, boid->position.y));
	boidShapes[index]->rotate(boid->rotation);
}

extern "C" void UpdateBoidData(Boid* boidList, int count)
{
	boidCount = count;
	for (int i = 0; i < count; ++i)
	{
		boidShapes[i]->setTexture(boidTexture);
		sf::Vector2f size = sf::Vector2f(boidTexture->getSize());
		boidShapes[i]->setSize(size);
		boidShapes[i]->setOrigin(size * 0.5f);

		boidShapes[i]->setPosition(sf::Vector2f(boidList[i].position.x, boidList[i].position.y));
		boidShapes[i]->setRotation(boidList[i].rotation);
	}
}

int main()
{
	//I tried doing this in assembly, but since I couldn't call the member functions and constructors for sfml, I ended up just making wrapper 
	//functions for each before realizing that that was kind of pointless, so I'm just doing the initial setup in c++

	//SFML Window Setup and loading assets
	sf::Clock* gameClock = new sf::Clock();
	boidTexture = new sf::Texture();
	boidTexture->loadFromFile("Assets/Boid.png");
	sf::Vector2f windowSize = sf::Vector2f(window->getSize());
	sf::Clock clock;
	sf::Event event;
	srand(time(NULL));

	fmod(rand(), 3.141592f * 2.0f);

	AsmInit(windowSize.x, windowSize.y, boidTexture->getSize().x);
	int fc = 0;
	//Game loop 
	while (window->isOpen())
	{
		float deltaTime = clock.getElapsedTime().asSeconds();
		clock.restart();
		sf::View view = window->getDefaultView();

		while (window->pollEvent(event))
		{
			switch (event.type)
			{
			case sf::Event::Closed:
				window->close();
				break;
			}
		}

		window->clear(sf::Color(100.0f, 100.0f, 100.0f));

		sf::Vector2f mouseWorldPosition = window->mapPixelToCoords(sf::Mouse::getPosition(*window));
		bool clickState = sf::Mouse::isButtonPressed(sf::Mouse::Left);
		AsmUpdate(deltaTime, mouseWorldPosition.x, mouseWorldPosition.y, clickState);

		for (int i = 0; i < boidCount; i++)
		{
			window->draw(*boidShapes[i]);
		}

		window->display();
	}

	return 0;
}
