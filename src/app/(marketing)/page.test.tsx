import { render, screen, within } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import Home from "@/app/(marketing)/page";
import { routes } from "@/lib/site";
describe("Home page",()=>{
 it("shows the messaging-first headline as the page's only h1",()=>{render(<Home/>);const headings=screen.getAllByRole("heading",{level:1});expect(headings).toHaveLength(1);expect(headings[0]).toHaveTextContent("Find your people. Start a conversation.");});
 it("sends calls to action to registration and sign in",()=>{render(<Home/>);expect(screen.getAllByRole("link",{name:"Get started"}).every((l)=>l.getAttribute("href")===routes.getStarted)).toBe(true);expect(screen.getByRole("link",{name:"I already have an account"})).toHaveAttribute("href",routes.signIn);});
 it("explains discovery, requests, and private chat in order",()=>{render(<Home/>);const steps=within(screen.getByRole("list")).getAllByRole("listitem");expect(steps).toHaveLength(3);expect(steps[0]).toHaveTextContent("Discover someone");expect(steps[1]).toHaveTextContent("Send a request");expect(steps[2]).toHaveTextContent("Start talking");});
 it("does not promise paid features or invented social proof",()=>{const {container}=render(<Home/>);expect(container.textContent).not.toMatch(/paid conversation|book a time|provider|★|testimonial|\brated\b/i);});
});